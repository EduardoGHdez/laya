// Writes vendor/pokedex.json from Showdown's own data, so Ruby never parses TypeScript.
const fs = require("fs");
const path = require("path");
const { Dex } = require(path.join(__dirname, "vendor/pokemon-showdown/dist/sim"));

const dex = Dex.forGen(9);
const moveTexts = dex.loadTextData().Moves;
const types = dex.types.all().filter((type) => !type.isNonstandard).map((type) => type.name);

const moves = {};
for (const move of dex.moves.all()) {
  moves[move.id] = {
    name: move.name,
    type: move.type,
    category: move.category,
    basePower: move.basePower,
    accuracy: move.accuracy,
    shortDesc: moveTexts[move.id]?.shortDesc ?? "",
  };
}

const species = {};
for (const s of dex.species.all()) species[s.id] = { name: s.name, types: s.types };

const effectiveness = {};
for (const attacking of types) {
  effectiveness[attacking] = {};
  for (const defending of types) {
    effectiveness[attacking][defending] = dex.getImmunity(attacking, defending)
      ? 2 ** dex.getEffectiveness(attacking, defending)
      : 0;
  }
}

fs.writeFileSync(path.join(__dirname, "vendor/pokedex.json"), JSON.stringify({ moves, species, effectiveness }));
console.log(`Wrote vendor/pokedex.json: ${Object.keys(moves).length} moves, ${Object.keys(species).length} species, ${types.length} types`);
