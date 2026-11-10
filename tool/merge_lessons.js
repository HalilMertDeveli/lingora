// Joins lesson part files (part1.json, part2.json, …) into assets/notes/lessons.json.
//   node tool/merge_lessons.js <dir>
const fs = require('fs');
const path = require('path');
const dir = process.argv[2];
const files = fs.readdirSync(dir).filter((f) => /^part\d+\.json$/.test(f))
  .sort((a, b) => parseInt(a.slice(4)) - parseInt(b.slice(4)));
const lessons = files.flatMap((f) => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')));
fs.writeFileSync(path.join(__dirname, '..', 'assets', 'notes', 'lessons.json'), JSON.stringify(lessons, null, 1) + '\n');
console.log(`lessons: ${lessons.length} from ${files.join(', ')}`);
