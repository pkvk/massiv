{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
module Data.Massiv.Array.ManifestSpec (spec) where

import Data.ByteString as S
import Data.ByteString.Builder as S
import Data.ByteString.Lazy as SL
import Data.Massiv.CoreArbitrary as A
import Data.Word (Word8)


-- ByteString
prop_toFromByteString :: Manifest r Ix1 Word8 => Array r Ix1 Word8 -> Property
prop_toFromByteString arr = toManifest arr === fromByteString (getComp arr) (toByteString arr)

prop_castToFromByteString :: Array S Ix1 Word8 -> Property
prop_castToFromByteString arr = arr === castFromByteString (getComp arr) (castToByteString arr)


prop_fromToByteString :: Comp -> [Word8] -> Property
prop_fromToByteString comp ls = bs === toByteString (fromByteString comp bs)
  where bs = S.pack ls

prop_toBuilder :: Array P Ix1 Word8 -> Property
prop_toBuilder arr = bs === SL.toStrict (S.toLazyByteString (toBuilder S.word8 arr))
  where bs = toByteString arr

conversionSpec :: Spec
conversionSpec =
  describe "ByteString" $ do
    it "castTo/TromByteString" $ property prop_castToFromByteString
    it "to/from ByteString P" $ property (prop_toFromByteString @P)
    it "to/from ByteString S" $ property (prop_toFromByteString @S)
    it "from/to ByteString" $ property prop_fromToByteString
    it "toBuilder" $ property prop_toBuilder


spec :: Spec
spec = describe "Conversion" conversionSpec
