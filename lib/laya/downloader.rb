require "fileutils"
require "net/http"
require "openssl"
require "uri"

module Laya
  # Resolves the directory that holds the model files: model_dir as-is, or the Hugging Face cache.
  # Files are fetched when missing or when their size differs from the remote one; each streams to a
  # .part file that is renamed when complete, so an interrupted download never leaves a broken file.
  class Downloader
    ORIGIN = URI("https://huggingface.co")
    MAX_REDIRECTS = 5
    NETWORK_ERRORS = [SocketError, SystemCallError, IOError, Timeout::Error,
                      OpenSSL::SSL::SSLError, Net::HTTPBadResponse].freeze

    def initialize(config)
      @config = config
    end

    def call
      return dir if @config.model_dir

      Configuration::BUNDLE_FILES.each { |file| fetch(file) }
      dir
    end

    def dir
      return File.expand_path(@config.model_dir) if @config.model_dir

      File.join(File.expand_path(@config.cache_dir), @config.repo.sub("/", "--"), @config.revision, *subfolder)
    end

    def missing_files
      Configuration::BUNDLE_FILES.reject { |file| File.file?(File.join(dir, file)) }
    end

    private

    def subfolder
      name = @config.subfolder.to_s.gsub(%r{\A/+|/+\z}, "")
      name.empty? ? [] : [name]
    end

    def url_for(file)
      path = [@config.repo, "resolve", URI.encode_www_form_component(@config.revision), *subfolder, file].join("/")
      "#{ORIGIN}/#{path}"
    end

    def fetch(file)
      destination = File.join(dir, file)
      url = url_for(file)
      if File.file?(destination)
        remote_size = remote_size(url)
        return if remote_size.nil? || remote_size == File.size(destination)
      end
      download(url, destination, file)
    end

    # A failed HEAD (offline, DNS, 5xx) means "unknown", so a populated cache keeps working offline.
    def remote_size(url)
      request(Net::HTTP::Head, url) do |response, linked_size|
        next Integer(linked_size, exception: false) if linked_size
        next nil unless response.is_a?(Net::HTTPSuccess)

        Integer(response["content-length"], exception: false)
      end
    rescue DownloadError, *NETWORK_ERRORS
      nil
    end

    def download(url, destination, file)
      FileUtils.mkdir_p(File.dirname(destination))
      partial = "#{destination}.part-#{Process.pid}"
      request(Net::HTTP::Get, url) do |response, _linked_size|
        raise DownloadError, failure_message(url, response) unless response.is_a?(Net::HTTPSuccess)

        write_body(response, partial, file, url)
      end
      File.rename(partial, destination)
      @config.logger&.info("laya: downloaded #{file}")
    rescue *NETWORK_ERRORS => e
      raise DownloadError, "failed to download #{url}: #{e.message}"
    ensure
      FileUtils.rm_f(partial) if partial
    end

    def write_body(response, partial, file, url)
      total = Integer(response["content-length"], exception: false)
      received = 0
      File.open(partial, "wb") do |output|
        response.read_body do |chunk|
          output.write(chunk)
          received += chunk.bytesize
          @config.on_progress&.call(file: file, received: received, total: total)
        end
      end
      raise DownloadError, "incomplete download of #{url}: got #{received} of #{total} bytes" if total && received != total
    end

    def failure_message(url, response)
      hint = [401, 403].include?(response.code.to_i) ? " (set HF_TOKEN or config.token for private or gated repos)" : ""
      "failed to download #{url}: #{response.code} #{response.message}#{hint}"
    end

    # Follows redirects and yields the final response (with its connection still open, for streaming)
    # plus the first x-linked-size seen, which Hugging Face only sends on the LFS redirect.
    def request(verb, url, hops: MAX_REDIRECTS, linked_size: nil, &block)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 60) do |http|
        http.request(build_request(verb, uri)) do |response|
          linked_size ||= response["x-linked-size"]
          # A HEAD stops at the LFS redirect: x-linked-size already answers it, and CDNs often refuse HEAD
          final = !response.is_a?(Net::HTTPRedirection) || (verb == Net::HTTP::Head && linked_size)
          return yield(response, linked_size) if final
          raise DownloadError, "too many redirects fetching #{url}" if hops.zero?

          return request(verb, URI.join(uri, response["location"]).to_s, hops: hops - 1, linked_size: linked_size, &block)
        end
      end
    end

    def build_request(verb, uri)
      verb.new(uri).tap do |request|
        request["User-Agent"] = "laya-ruby/#{VERSION}"
        request["Accept-Encoding"] = "identity" # sizes must match the bytes on disk
        request["Authorization"] = "Bearer #{@config.token}" if @config.token && uri.host == ORIGIN.host
      end
    end
  end
end
