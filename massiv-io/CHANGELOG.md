# 0.1.6

* Made it compatible with new `massiv >= 0.3` as well as the old ones.

# 0.1.5

* All decoded images will be read in sequentially, but will have default computation set to `Par`.

# 0.1.4

* Fixed wrongful export of `Bit` constructor.
* Added export of `fromDynamicImage` and `fromAnyDynamicImage`

# 0.1.3

* Fixed #22 - Invalid guard against image size
* Made sure format is inferred from all supported file extensions for auto decoding.

# 0.1.2

* Exposed `Elevator` internal functions.
* Deprecate ColorSpace specific functions (`liftPx`, `foldlPx`, etc.) in favor of Functor,
  Applicative and Foldable.

# 0.1.1

* Addition of `Ord` instances to Pixels.

# 0.1.0

* Initial Release
