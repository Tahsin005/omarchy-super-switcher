import QtQuick
import QtTest
import ".."
import "../IconGeometry.js" as Geometry

TestCase {
  id: testCase
  name: "SwitcherIconRendering"
  when: windowShown
  width: 512
  height: 512

  Component {
    id: iconComponent
    SwitcherIcon {}
  }

  Canvas {
    id: capture
    width: 210
    height: 210
    opacity: 0
    property var result: null
    property var bounds: null
    onImageLoaded: requestPaint()
    onPaint: {
      if (!result || !isImageLoaded(result.url)) return
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      ctx.drawImage(result.url, 0, 0, width, height)
      bounds = Geometry.alphaBounds(ctx.getImageData(0, 0, width, height).data, width, height)
      unloadImage(result.url)
      result = null
    }
  }

  function renderedBounds(icon) {
    capture.bounds = null
    verify(icon.grabToImage(function(result) {
      capture.result = result
      capture.loadImage(result.url)
      capture.requestPaint()
    }, Qt.size(210, 210)))
    tryVerify(function() { return capture.bounds !== null }, 3000)
    return capture.bounds
  }

  function test_artwork_data() {
    return [
      { tag: "solid-96", file: "icon-solid.svg", size: 96 },
      { tag: "padded-96", file: "icon-padded.svg", size: 96 },
      { tag: "solid-105", file: "icon-solid.svg", size: 105 },
      { tag: "padded-105", file: "icon-padded.svg", size: 105 }
    ]
  }

  function test_artwork(data) {
    var source = Qt.resolvedUrl("fixtures/" + data.file)
    // Each row exercises cold sampling, then reopening from the shared cache.
    delete Geometry.measuredBounds[String(source)]
    for (var pass = 0; pass < 2; pass++) {
      var icon = createTemporaryObject(iconComponent, testCase, {
        width: data.size, height: data.size, source: source
      })
      verify(icon !== null)
      tryVerify(function() { return icon.bounds !== null }, 3000)
      if (data.file === "icon-solid.svg") {
        compare(icon.bounds.x, 0)
        compare(icon.bounds.y, 0)
        compare(icon.bounds.width, 210)
        compare(icon.bounds.height, 210)
      } else {
        fuzzyCompare(icon.bounds.x, 12, 1)
        fuzzyCompare(icon.bounds.y, 34, 1)
        fuzzyCompare(icon.bounds.width, 140, 1)
        fuzzyCompare(icon.bounds.height, 100, 1)
      }
      var bounds = renderedBounds(icon)
      var ratio = data.size / 210
      fuzzyCompare(Math.max(bounds.width, bounds.height) * ratio, 84, 2)
      fuzzyCompare((bounds.x + bounds.width / 2) * ratio, data.size / 2, 1)
      fuzzyCompare((bounds.y + bounds.height / 2) * ratio, data.size / 2, 1)
      icon.destroy()
    }
  }
}
