{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
-- |
-- Module      : Data.Massiv.Array.Numeric
-- Copyright   : (c) Alexey Kuleshevich 2018-2019
-- License     : BSD3
-- Maintainer  : Alexey Kuleshevich <lehins@yandex.ru>
-- Stability   : experimental
-- Portability : non-portable
--
module Data.Massiv.Array.Numeric
  ( -- * Num
    (.+)
  , (.-)
  , (.*)
  , (.^)
  , (|*|)
  , multiplyTransposed
  , negateA
  , absA
  , signumA
  , fromIntegerA
  -- * Integral
  , quotA
  , remA
  , divA
  , modA
  , quotRemA
  , divModA
  -- * Fractional
  , (./)
  , (.^^)
  , recipA
  , fromRationalA
  -- * Floating
  , piA
  , expA
  , logA
  , sqrtA
  , (.**)
  , logBaseA
  , sinA
  , cosA
  , tanA
  , asinA
  , acosA
  , atanA
  , sinhA
  , coshA
  , tanhA
  , asinhA
  , acoshA
  , atanhA
  -- * RealFrac
  , truncateA
  , roundA
  , ceilingA
  , floorA
  -- * RealFloat
  , atan2A
  ) where

import Data.Massiv.Array.Delayed.Pull
import Data.Massiv.Array.Manifest.Internal
import Data.Massiv.Array.Ops.Fold as A
import Data.Massiv.Array.Ops.Map as A
import Data.Massiv.Array.Ops.Transform as A
import Data.Massiv.Core
import Data.Massiv.Core.Common
import Data.Massiv.Core.Index.Internal (Sz(SafeSz))
import Prelude as P


infixr 8  .^, .^^
infixl 7  .*, ./, `quotA`, `remA`, `divA`, `modA`
infixl 6  .+, .-

liftArray2Matching
  :: (Source r1 ix a, Source r2 ix b)
  => (a -> b -> e) -> Array r1 ix a -> Array r2 ix b -> Array D ix e
liftArray2Matching f !arr1 !arr2
  | sz1 == sz2 =
    makeArray
      (getComp arr1 <> getComp arr2)
      sz1
      (\ !ix -> f (unsafeIndex arr1 ix) (unsafeIndex arr2 ix))
  | otherwise = throw $ SizeMismatchException (size arr1) (size arr2)
  where
    sz1 = size arr1
    sz2 = size arr2
{-# INLINE liftArray2Matching #-}


(.+)
  :: (Source r1 ix e, Source r2 ix e, Num e)
  => Array r1 ix e -> Array r2 ix e -> Array D ix e
(.+) = liftArray2Matching (+)
{-# INLINE (.+) #-}

(.-)
  :: (Source r1 ix e, Source r2 ix e, Num e)
  => Array r1 ix e -> Array r2 ix e -> Array D ix e
(.-) = liftArray2Matching (-)
{-# INLINE (.-) #-}

(.*)
  :: (Source r1 ix e, Source r2 ix e, Num e)
  => Array r1 ix e -> Array r2 ix e -> Array D ix e
(.*) = liftArray2Matching (*)
{-# INLINE (.*) #-}

(.^)
  :: (Source r ix e, Num e, Integral b)
  => Array r ix e -> b -> Array D ix e
(.^) arr n = liftArray (^ n) arr
{-# INLINE (.^) #-}

-- | Perform matrix multiplication. Inner dimensions must agree, otherwise `SizeMismatchException`.
(|*|) ::
     (Mutable r Ix2 e, Source r' Ix2 e, OuterSlice r Ix2 e, Source (EltRepr r Ix2) Ix1 e, Num e)
  => Array r Ix2 e
  -> Array r' Ix2 e
  -> Array r Ix2 e
(|*|) a1 = compute . multArrs a1
{-# INLINE [1] (|*|) #-}

{-# RULES
"multDoubleTranspose" [~1] forall arr1 arr2 . arr1 |*| transpose arr2 =
    multiplyTransposedFused arr1 (convert arr2)
 #-}

multiplyTransposedFused ::
     ( Mutable r Ix2 e
     , OuterSlice r Ix2 e
     , Source (EltRepr r Ix2) Ix1 e
     , Num e
     )
  => Array r Ix2 e
  -> Array r Ix2 e
  -> Array r Ix2 e
multiplyTransposedFused arr1 arr2 = compute (multiplyTransposed arr1 arr2)
{-# INLINE multiplyTransposedFused #-}


multArrs :: forall r r' e.
            ( Mutable r Ix2 e
            , Source r' Ix2 e
            , OuterSlice r Ix2 e
            , Source (EltRepr r Ix2) Ix1 e
            , Num e
            )
         => Array r Ix2 e -> Array r' Ix2 e -> Array D Ix2 e
multArrs arr1 arr2 = multiplyTransposed arr1 arr2'
  where
    arr2' :: Array r Ix2 e
    arr2' = compute $ transpose arr2
{-# INLINE multArrs #-}

-- | It is quite often that second matrix gets transposed before multiplication (eg. A * A'), but
-- due to layout of data in memory it is more efficient to transpose the second array again.
multiplyTransposed ::
     ( Manifest r Ix2 e
     , OuterSlice r Ix2 e
     , Source (EltRepr r Ix2) Ix1 e
     , Num e
     )
  => Array r Ix2 e
  -> Array r Ix2 e
  -> Array D Ix2 e
multiplyTransposed arr1 arr2
  | n1 /= m2 = throw $ SizeMismatchException (size arr1) (size arr2)
  | otherwise =
    DArray (getComp arr1 <> getComp arr2) (SafeSz (m1 :. n2)) $ \(i :. j) ->
      A.foldlS (+) 0 (A.zipWith (*) (unsafeOuterSlice arr1 i) (unsafeOuterSlice arr2 j))
  where
    SafeSz (m1 :. n1) = size arr1
    SafeSz (n2 :. m2) = size arr2
{-# INLINE multiplyTransposed #-}


negateA
  :: (Source r ix e, Num e)
  => Array r ix e -> Array D ix e
negateA = liftArray negate
{-# INLINE negateA #-}

absA
  :: (Source r ix e, Num e)
  => Array r ix e -> Array D ix e
absA = liftArray abs
{-# INLINE absA #-}

signumA
  :: (Source r ix e, Num e)
  => Array r ix e -> Array D ix e
signumA = liftArray signum
{-# INLINE signumA #-}

fromIntegerA
  :: (Index ix, Num e)
  => Integer -> Array D ix e
fromIntegerA = singleton . fromInteger
{-# INLINE fromIntegerA #-}

(./)
  :: (Source r1 ix e, Source r2 ix e, Fractional e)
  => Array r1 ix e -> Array r2 ix e -> Array D ix e
(./) = liftArray2Matching (/)
{-# INLINE (./) #-}

(.^^)
  :: (Source r ix e, Fractional e, Integral b)
  => Array r ix e -> b -> Array D ix e
(.^^) arr n = liftArray (^^ n) arr
{-# INLINE (.^^) #-}

recipA
  :: (Source r ix e, Fractional e)
  => Array r ix e -> Array D ix e
recipA = liftArray recip
{-# INLINE recipA #-}


fromRationalA
  :: (Index ix, Fractional e)
  => Rational -> Array D ix e
fromRationalA = singleton . fromRational
{-# INLINE fromRationalA #-}

piA
  :: (Index ix, Floating e)
  => Array D ix e
piA = singleton pi
{-# INLINE piA #-}

expA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
expA = liftArray exp
{-# INLINE expA #-}

sqrtA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
sqrtA = liftArray exp
{-# INLINE sqrtA #-}

logA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
logA = liftArray log
{-# INLINE logA #-}

logBaseA
  :: (Source r1 ix e, Source r2 ix e, Floating e)
  => Array r1 ix e -> Array r2 ix e -> Array D ix e
logBaseA = liftArray2Matching logBase
{-# INLINE logBaseA #-}

(.**)
  :: (Source r1 ix e, Source r2 ix e, Floating e)
  => Array r1 ix e -> Array r2 ix e -> Array D ix e
(.**) = liftArray2Matching (**)
{-# INLINE (.**) #-}



sinA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
sinA = liftArray sin
{-# INLINE sinA #-}

cosA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
cosA = liftArray cos
{-# INLINE cosA #-}

tanA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
tanA = liftArray cos
{-# INLINE tanA #-}

asinA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
asinA = liftArray asin
{-# INLINE asinA #-}

atanA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
atanA = liftArray atan
{-# INLINE atanA #-}

acosA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
acosA = liftArray acos
{-# INLINE acosA #-}

sinhA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
sinhA = liftArray sinh
{-# INLINE sinhA #-}

tanhA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
tanhA = liftArray cos
{-# INLINE tanhA #-}

coshA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
coshA = liftArray cosh
{-# INLINE coshA #-}

asinhA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
asinhA = liftArray asinh
{-# INLINE asinhA #-}

acoshA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
acoshA = liftArray acosh
{-# INLINE acoshA #-}

atanhA
  :: (Source r ix e, Floating e)
  => Array r ix e -> Array D ix e
atanhA = liftArray atanh
{-# INLINE atanhA #-}


quotA
  :: (Source r1 ix e, Source r2 ix e, Integral e)
  => Array r1 ix e -> Array r2 ix e -> Array D ix e
quotA = liftArray2Matching (quot)
{-# INLINE quotA #-}


remA
  :: (Source r1 ix e, Source r2 ix e, Integral e)
  => Array r1 ix e -> Array r2 ix e -> Array D ix e
remA = liftArray2Matching (rem)
{-# INLINE remA #-}

divA
  :: (Source r1 ix e, Source r2 ix e, Integral e)
  => Array r1 ix e -> Array r2 ix e -> Array D ix e
divA = liftArray2Matching (div)
{-# INLINE divA #-}

modA
  :: (Source r1 ix e, Source r2 ix e, Integral e)
  => Array r1 ix e -> Array r2 ix e -> Array D ix e
modA = liftArray2Matching (mod)
{-# INLINE modA #-}



quotRemA
  :: (Source r1 ix e, Source r2 ix e, Integral e)
  => Array r1 ix e -> Array r2 ix e -> (Array D ix e, Array D ix e)
quotRemA arr1 = A.unzip . liftArray2Matching (quotRem) arr1
{-# INLINE quotRemA #-}


divModA
  :: (Source r1 ix e, Source r2 ix e, Integral e)
  => Array r1 ix e -> Array r2 ix e -> (Array D ix e, Array D ix e)
divModA arr1 = A.unzip . liftArray2Matching (divMod) arr1
{-# INLINE divModA #-}



truncateA
  :: (Source r ix a, RealFrac a, Integral b)
  => Array r ix a -> Array D ix b
truncateA = liftArray truncate
{-# INLINE truncateA #-}


roundA
  :: (Source r ix a, RealFrac a, Integral b)
  => Array r ix a -> Array D ix b
roundA = liftArray round
{-# INLINE roundA #-}


ceilingA
  :: (Source r ix a, RealFrac a, Integral b)
  => Array r ix a -> Array D ix b
ceilingA = liftArray ceiling
{-# INLINE ceilingA #-}


floorA
  :: (Source r ix a, RealFrac a, Integral b)
  => Array r ix a -> Array D ix b
floorA = liftArray floor
{-# INLINE floorA #-}

atan2A
  :: (Source r ix e, RealFloat e)
  => Array r ix e -> Array r ix e -> Array D ix e
atan2A = liftArray2Matching atan2
{-# INLINE atan2A #-}

