const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const context = { module: { exports: {} } }
vm.runInNewContext(fs.readFileSync("IconGeometry.js", "utf8").replace(/^\.pragma library\s*/, ""), context)
const geometry = context.module.exports

function image(size, rect) {
  const pixels = new Uint8ClampedArray(size * size * 4)
  for (let y = rect.y; y < rect.y + rect.height; y++) {
    for (let x = rect.x; x < rect.x + rect.width; x++) pixels[(y * size + x) * 4 + 3] = 255
  }
  return pixels
}

test("finds artwork inside asymmetric transparent padding and ignores faint shadows", () => {
  const pixels = image(210, { x: 14, y: 30, width: 160, height: 170 })
  pixels[3] = 20
  assert.deepEqual(JSON.parse(JSON.stringify(geometry.alphaBounds(pixels, 210, 210))),
    { x: 14, y: 30, width: 160, height: 170 })
})

test("large and padded icons share an 84px visible footprint without stretching", () => {
  for (const bounds of [
    { x: 0, y: 0, width: 210, height: 210 },
    { x: 20, y: 20, width: 170, height: 170 },
    { x: 10, y: 45, width: 180, height: 110 },
  ]) {
    const position = geometry.placement(bounds, 210, 168)
    assert.equal(Math.max(bounds.width, bounds.height) * position.scale / 2, 84)
    assert.equal((bounds.x + bounds.width / 2) * position.scale + position.x, 105)
    assert.equal((bounds.y + bounds.height / 2) * position.scale + position.y, 105)
  }
})

test("fully transparent and invalid bounds do not produce an infinite transform", () => {
  assert.equal(geometry.alphaBounds(new Uint8ClampedArray(16), 2, 2), null)
  assert.equal(geometry.placement(null, 210, 168), null)
  assert.equal(geometry.placement({ x: 0, y: 0, width: 0, height: 0 }, 210, 168), null)
})
