import QtQuick
import "IconGeometry.js" as Geometry

// Keep the native image renderer; sample its rendered alpha once per source.
Item {
  id: root

  required property url source
  property real artworkSize: 84
  readonly property int sampleSize: 210
  property url displaySource: source
  property var bounds: null
  property var grabResult: null
  property bool measuring: false
  readonly property var placement: root.width > 0 ? Geometry.placement(root.bounds, root.sampleSize, root.artworkSize * root.sampleSize / root.width) : null

  function measure() {
    if (!sampler.available || original.status !== Image.Ready || root.measuring || root.bounds) return
    var key = String(root.displaySource)
    if (Geometry.measuredBounds[key] !== undefined) {
      root.bounds = Geometry.measuredBounds[key]
      return
    }
    root.measuring = true
    // Capture Qt's actual rendering, then sample it on one fixed pixel grid.
    // Theme image providers can otherwise report different native DPRs.
    var started = original.grabToImage(function(result) {
      if (!root || key !== String(root.displaySource)) return
      root.grabResult = result
      sampler.loadImage(result.url)
      // Item grabs can load synchronously without an imageLoaded signal.
      sampler.requestPaint()
    }, Qt.size(root.sampleSize, root.sampleSize))
    if (!started) root.measuring = false
  }

  Image {
    id: original
    width: root.placement ? root.width * root.placement.scale : root.artworkSize
    height: root.placement ? root.height * root.placement.scale : root.artworkSize
    x: root.placement ? root.placement.x * root.width / root.sampleSize : (root.width - width) / 2
    y: root.placement ? root.placement.y * root.height / root.sampleSize : (root.height - height) / 2
    source: root.displaySource
    sourceSize: Qt.size(root.sampleSize, root.sampleSize)
    fillMode: Image.PreserveAspectFit
    cache: true
    onStatusChanged: {
      if (status === Image.Ready) Qt.callLater(root.measure)
      else if (status === Image.Error && source !== Qt.resolvedUrl("assets/default-app.svg"))
        root.displaySource = Qt.resolvedUrl("assets/default-app.svg")
    }
  }

  Canvas {
    id: sampler
    anchors.fill: parent
    canvasSize: Qt.size(root.sampleSize, root.sampleSize)
    renderTarget: Canvas.Image
    contextType: "2d"
    onAvailableChanged: if (available) Qt.callLater(root.measure)
    onImageLoaded: requestPaint()
    onPaint: sample()
    function sample() {
      if (!root.grabResult || !isImageLoaded(root.grabResult.url)) return
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, root.sampleSize, root.sampleSize)
      ctx.drawImage(root.grabResult.url, 0, 0, root.sampleSize, root.sampleSize)
      root.bounds = Geometry.alphaBounds(ctx.getImageData(0, 0, root.sampleSize, root.sampleSize).data, root.sampleSize, root.sampleSize)
      ctx.clearRect(0, 0, root.sampleSize, root.sampleSize)
      Geometry.measuredBounds[String(root.displaySource)] = root.bounds
      unloadImage(root.grabResult.url)
      root.grabResult = null
      root.measuring = false
    }
  }

  onDisplaySourceChanged: {
    root.bounds = null
    root.grabResult = null
    root.measuring = false
    Qt.callLater(root.measure)
  }
  onSourceChanged: root.displaySource = source
}
