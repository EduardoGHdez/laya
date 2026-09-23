module Laya
  # `laya download` / `laya path`, shared by exe/laya and the Rake tasks.
  class CLI
    EX_USAGE = 64
    ENV_OVERRIDES = {
      cache_dir: "LAYA_CACHE",
      token: "HF_TOKEN",
      repo: "LAYA_REPO",
      revision: "LAYA_REVISION",
      subfolder: "LAYA_SUBFOLDER"
    }.freeze

    def initialize(out: $stdout, err: $stderr, env: ENV)
      @out = out
      @err = err
      @env = env
    end

    def run(argv)
      case argv.first
      when "download" then download
      when "path" then path
      when "help", "-h", "--help"
        @out.puts help
        0
      when nil
        @err.puts help
        EX_USAGE
      else
        @err.puts "laya: unknown command #{argv.first.inspect}", "", help
        EX_USAGE
      end
    end

    def help
      settings = config
      <<~HELP
        laya #{VERSION}: manage the Laya model files

        Usage:
          laya download   Download the model into the cache (~1.7 GB the first time)
          laya path       Print the model directory; exits 1 if files are missing
          laya help       Show this message

        Environment (overrides Laya.configure):
          LAYA_CACHE      Cache directory         #{settings.cache_dir}
          HF_TOKEN        Hugging Face token      #{settings.token ? "set" : "not set"}
          LAYA_REPO       Hugging Face repo       #{settings.repo}
          LAYA_REVISION   Branch, tag or commit   #{settings.revision}
          LAYA_SUBFOLDER  Subfolder in the repo   #{settings.subfolder || "none"}

        Examples:
          laya download
          LAYA_CACHE=/models laya download
          ls "$(laya path)"
      HELP
    end

    private

    def config
      overrides = ENV_OVERRIDES.to_h { |setting, variable| [setting, @env[variable]] }.compact
      Laya.config.merge(**overrides)
    end

    def download
      settings = config
      downloader = Downloader.new(settings.merge(on_progress: progress).validate!)
      @err.puts "Downloading #{settings.repo}@#{settings.revision} into #{downloader.dir}" unless settings.model_dir
      dir = downloader.call
      @err.puts "Model ready in #{dir}"
      @out.puts dir
      0
    rescue Laya::Error => e
      @err.puts "", "laya: #{e.message}"
      1
    end

    def path
      downloader = Downloader.new(config)
      missing_files = downloader.missing_files
      if missing_files.empty?
        @out.puts downloader.dir
        0
      else
        @err.puts "laya: #{downloader.dir} is missing:"
        missing_files.each { |file| @err.puts "  #{file}" }
        @err.puts "Run `laya download` to fetch them."
        1
      end
    end

    def progress
      last_percent = {}
      lambda do |file:, received:, total:|
        percent = total&.positive? ? received * 100 / total : nil
        next if percent && last_percent[file] == percent

        last_percent[file] = percent
        @err.print "\r  #{file.ljust(32)} #{progress_detail(percent, received, total)}"
        @err.puts if percent == 100
      end
    end

    def progress_detail(percent, received, total)
      return megabytes(received) unless percent

      "#{percent.to_s.rjust(3)}%  #{megabytes(received)} / #{megabytes(total)}"
    end

    def megabytes(bytes) = format("%.1f MB", bytes / 1_048_576.0)
  end
end
