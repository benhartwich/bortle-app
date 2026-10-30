// The optics calculator's arithmetic: image scale, field of view, f-ratio, resolving
// power and whether the camera samples the seeing well. Plain formulas; the verdicts are
// rules of thumb and say so.

class Optics {
  const Optics({
    required this.focalMm,
    required this.apertureMm,
    required this.pixelUm,
    required this.widthPx,
    required this.heightPx,
    this.seeingArcsec = 2.5,
    this.binning = 1,
  });

  final double focalMm;
  final double apertureMm;
  final double pixelUm;
  final int widthPx;
  final int heightPx;

  /// The site's typical seeing (FWHM), in arcseconds.
  final double seeingArcsec;
  final int binning;

  double get fRatio => focalMm / apertureMm;

  /// Arcseconds per pixel (206.265 × pixel size in µm ÷ focal length in mm).
  double get scale => 206.265 * pixelUm * binning / focalMm;

  /// Field of view in arcminutes.
  double get fieldWidth => scale * widthPx / binning / 60;
  double get fieldHeight => scale * heightPx / binning / 60;

  /// The sensor's size in millimetres.
  double get sensorWidthMm => pixelUm * widthPx / 1000;
  double get sensorHeightMm => pixelUm * heightPx / 1000;

  /// Dawes' limit in arcseconds: two equal stars just apart.
  double get dawes => 116 / apertureMm;

  /// The pixels a star of the given seeing spans (FWHM / scale); about 2–3 is the
  /// range worth aiming for.
  double get pixelsPerFwhm => seeingArcsec / scale;

  Sampling get sampling {
    final p = pixelsPerFwhm;
    if (p < 1.5) return Sampling.under;
    if (p > 3.5) return Sampling.over;
    return Sampling.good;
  }

  /// How much of the field's shorter side an object of [sizeArcmin] fills, 0..1+.
  double fill(double sizeArcmin) => sizeArcmin / (fieldWidth < fieldHeight ? fieldWidth : fieldHeight);
}

enum Sampling { under, good, over }
