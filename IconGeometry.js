.pragma library

// Cache only source geometry, not theme colors or rendered pixels.
var measuredBounds = Object.create(null)

function alphaBounds(pixels, width, height) {
    var left = width, top = height, right = -1, bottom = -1
    for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
            // Ignore faint drop shadows when measuring the artwork itself.
            if (pixels[(y * width + x) * 4 + 3] < 32) continue
            left = Math.min(left, x)
            top = Math.min(top, y)
            right = Math.max(right, x)
            bottom = Math.max(bottom, y)
        }
    }
    return right < left ? null : { x: left, y: top, width: right - left + 1, height: bottom - top + 1 }
}

function placement(bounds, canvasSize, artworkSize) {
    if (!bounds || Math.max(bounds.width, bounds.height) <= 0) return null
    var scale = artworkSize / Math.max(bounds.width, bounds.height)
    return {
        scale: scale,
        x: canvasSize / 2 - (bounds.x + bounds.width / 2) * scale,
        y: canvasSize / 2 - (bounds.y + bounds.height / 2) * scale
    }
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { alphaBounds: alphaBounds, placement: placement }
}
