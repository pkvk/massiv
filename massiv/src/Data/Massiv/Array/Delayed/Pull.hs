{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
-- |
-- Module      : Data.Massiv.Array.Delayed.Pull
-- Copyright   : (c) Alexey Kuleshevich 2018-2019
-- License     : BSD3
-- Maintainer  : Alexey Kuleshevich <lehins@yandex.ru>
-- Stability   : experimental
-- Portability : non-portable
--
module Data.Massiv.Array.Delayed.Pull
  ( D(..)
  , Array(..)
  , delay
  , eq
  , ord
  , liftArray
  , liftArray2
  ) where

import qualified Data.Foldable as F
import Data.Massiv.Array.Ops.Fold.Internal as A
import Data.Massiv.Core.Common
import Data.Massiv.Core.Index.Internal
import Data.Massiv.Core.List (L, showArrayList, showsArrayPrec)
import GHC.Base (build)
import Prelude hiding (zipWith)

#include "massiv.h"

-- | Delayed representation.
data D = D deriving Show

data instance Array D ix e = DArray { dComp :: !Comp
                                    , dSize :: !(Sz ix)
                                    , dIndex :: ix -> e }
type instance EltRepr D ix = D

instance (Ragged L ix e, Show e) => Show (Array D ix e) where
  showsPrec = showsArrayPrec id
  showList = showArrayList

instance Index ix => Resize D ix where
  unsafeResize !sz !arr =
    DArray (dComp arr) sz $ \ !ix ->
      unsafeIndex arr (fromLinearIndex (size arr) (toLinearIndex sz ix))
  {-# INLINE unsafeResize #-}

instance Index ix => Extract D ix e where
  unsafeExtract !sIx !newSz !arr =
    DArray (dComp arr) newSz $ \ !ix ->
      unsafeIndex arr (liftIndex2 (+) ix sIx)
  {-# INLINE unsafeExtract #-}


instance Index ix => Construct D ix e where
  setComp c arr = arr { dComp = c }
  {-# INLINE setComp #-}

  makeArray = DArray
  {-# INLINE makeArray #-}


instance Index ix => Source D ix e where
  unsafeIndex = INDEX_CHECK("(Source D ix e).unsafeIndex", size, dIndex)
  {-# INLINE unsafeIndex #-}


instance ( Index ix
         , Index (Lower ix)
         , Elt D ix e ~ Array D (Lower ix) e
         ) =>
         Slice D ix e where
  unsafeSlice arr start cut@(SafeSz cutSz) dim = do
    newSz <- dropDimM cutSz dim
    return $ unsafeResize (SafeSz newSz) (unsafeExtract start cut arr)
  {-# INLINE unsafeSlice #-}


instance (Elt D ix e ~ Array D (Lower ix) e, Index ix) => OuterSlice D ix e where

  unsafeOuterSlice !arr !i =
    DArray (dComp arr) (snd (unconsSz (size arr))) (\ !ix -> unsafeIndex arr (consDim i ix))
  {-# INLINE unsafeOuterSlice #-}

instance (Elt D ix e ~ Array D (Lower ix) e, Index ix) => InnerSlice D ix e where

  unsafeInnerSlice !arr (szL, _) !i =
    DArray (dComp arr) szL (\ !ix -> unsafeIndex arr (snocDim ix i))
  {-# INLINE unsafeInnerSlice #-}


instance (Eq e, Index ix) => Eq (Array D ix e) where
  (==) = eq (==)
  {-# INLINE (==) #-}

instance (Ord e, Index ix) => Ord (Array D ix e) where
  compare = ord compare
  {-# INLINE compare #-}

instance Functor (Array D ix) where
  fmap f (DArray c sz g) = DArray c sz (f . g)
  {-# INLINE fmap #-}


instance Index ix => Applicative (Array D ix) where
  pure = singleton
  {-# INLINE pure #-}
  (<*>) (DArray c1 (SafeSz sz1) uIndex1) (DArray c2 (SafeSz sz2) uIndex2) =
    DArray (c1 <> c2) (SafeSz (liftIndex2 min sz1 sz2)) $ \ !ix ->
      (uIndex1 ix) (uIndex2 ix)
  {-# INLINE (<*>) #-}


-- | Row-major sequential folding over a Delayed array.
instance Index ix => Foldable (Array D ix) where
  fold = A.fold
  {-# INLINE fold #-}
  foldMap = A.foldMono
  {-# INLINE foldMap #-}
  foldl = lazyFoldlS
  {-# INLINE foldl #-}
  foldl' = foldlS
  {-# INLINE foldl' #-}
  foldr = foldrFB
  {-# INLINE foldr #-}
  foldr' = foldrS
  {-# INLINE foldr' #-}
  null (DArray _ sz _) = totalElem sz == 0
  {-# INLINE null #-}
  length = totalElem . size
  {-# INLINE length #-}
  toList arr = build (\ c n -> foldrFB c n arr)
  {-# INLINE toList #-}


instance Index ix => Load D ix e where
  size = dSize
  {-# INLINE size #-}
  getComp = dComp
  {-# INLINE getComp #-}
  loadArrayM !scheduler !arr =
    splitLinearlyWith_ scheduler (elemsCount arr) (unsafeLinearIndex arr)
  {-# INLINE loadArrayM #-}

instance Index ix => StrideLoad D ix e

instance (Index ix, Num e) => Num (Array D ix e) where
  (+)         = liftArray2 (+)
  {-# INLINE (+) #-}
  (-)         = liftArray2 (-)
  {-# INLINE (-) #-}
  (*)         = liftArray2 (*)
  {-# INLINE (*) #-}
  abs         = liftArray abs
  {-# INLINE abs #-}
  signum      = liftArray signum
  {-# INLINE signum #-}
  fromInteger = singleton . fromInteger
  {-# INLINE fromInteger #-}

instance (Index ix, Fractional e) => Fractional (Array D ix e) where
  (/)          = liftArray2 (/)
  {-# INLINE (/) #-}
  fromRational = singleton . fromRational
  {-# INLINE fromRational #-}


instance (Index ix, Floating e) => Floating (Array D ix e) where
  pi    = singleton pi
  {-# INLINE pi #-}
  exp   = liftArray exp
  {-# INLINE exp #-}
  log   = liftArray log
  {-# INLINE log #-}
  sin   = liftArray sin
  {-# INLINE sin #-}
  cos   = liftArray cos
  {-# INLINE cos #-}
  asin  = liftArray asin
  {-# INLINE asin #-}
  atan  = liftArray atan
  {-# INLINE atan #-}
  acos  = liftArray acos
  {-# INLINE acos #-}
  sinh  = liftArray sinh
  {-# INLINE sinh #-}
  cosh  = liftArray cosh
  {-# INLINE cosh #-}
  asinh = liftArray asinh
  {-# INLINE asinh #-}
  atanh = liftArray atanh
  {-# INLINE atanh #-}
  acosh = liftArray acosh
  {-# INLINE acosh #-}



-- | /O(1)/ Conversion from a source array to `D` representation.
delay :: Source r ix e => Array r ix e -> Array D ix e
delay arr = DArray (getComp arr) (size arr) (unsafeIndex arr)
{-# INLINE [1] delay #-}

{-# RULES
"delay" [~1] forall (arr :: Array D ix e) . delay arr = arr
 #-}

-- TODO: switch to zipWith
-- | /O(min (n1, n2))/ - Compute array equality by applying a comparing function to each element.
eq :: (Source r1 ix e1, Source r2 ix e2) =>
      (e1 -> e2 -> Bool) -> Array r1 ix e1 -> Array r2 ix e2 -> Bool
eq f arr1 arr2 =
  (size arr1 == size arr2) &&
  F.and
    (DArray (getComp arr1 <> getComp arr2) (size arr1) $ \ix ->
       f (unsafeIndex arr1 ix) (unsafeIndex arr2 ix))
{-# INLINE eq #-}

-- | /O(min (n1, n2))/ - Compute array ordering by applying a comparing function to each element.
-- The exact ordering is unspecified so this is only intended for use in maps and the like where
-- you need an ordering but do not care about which one is used.
ord :: (Source r1 ix e1, Source r2 ix e2) =>
       (e1 -> e2 -> Ordering) -> Array r1 ix e1 -> Array r2 ix e2 -> Ordering
ord f arr1 arr2 =
  compare (size arr1) (size arr2) <>
  A.fold
    (DArray (getComp arr1 <> getComp arr2) (size arr1) $ \ix ->
       f (unsafeIndex arr1 ix) (unsafeIndex arr2 ix))
{-# INLINE ord #-}

-- | The usual map.
liftArray :: Source r ix b => (b -> e) -> Array r ix b -> Array D ix e
liftArray f !arr = DArray (getComp arr) (size arr) (f . unsafeIndex arr)
{-# INLINE liftArray #-}

-- | Similar to `Data.Massiv.Array.zipWith`, except dimensions of both arrays either have to be the
-- same, or at least one of the two array must be a singleton array, in which case it will behave as
-- a `Data.Massiv.Array.map`.
--
-- @since 0.1.4
liftArray2
  :: (Source r1 ix a, Source r2 ix b)
  => (a -> b -> e) -> Array r1 ix a -> Array r2 ix b -> Array D ix e
liftArray2 f !arr1 !arr2
  | sz1 == oneSz = liftArray (f (unsafeIndex arr1 zeroIndex)) arr2
  | sz2 == oneSz = liftArray (`f` unsafeIndex arr2 zeroIndex) arr1
  | sz1 == sz2 =
    DArray (getComp arr1 <> getComp arr2) sz1 (\ !ix -> f (unsafeIndex arr1 ix) (unsafeIndex arr2 ix))
  | otherwise = throw $ SizeMismatchException (size arr1) (size arr2)
  where
    sz1 = size arr1
    sz2 = size arr2
{-# INLINE liftArray2 #-}


