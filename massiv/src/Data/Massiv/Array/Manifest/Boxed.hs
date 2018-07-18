{-# LANGUAGE BangPatterns          #-}
{-# LANGUAGE CPP                   #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MagicHash             #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE UndecidableInstances  #-}
-- |
-- Module      : Data.Massiv.Array.Manifest.Boxed
-- Copyright   : (c) Alexey Kuleshevich 2018
-- License     : BSD3
-- Maintainer  : Alexey Kuleshevich <lehins@yandex.ru>
-- Stability   : experimental
-- Portability : non-portable
--
module Data.Massiv.Array.Manifest.Boxed
  ( B(..)
  , N (..)
  , Array(..)
  , toBoxedArray
  , fromBoxedArray
  , toMutableBoxedArray
  , fromMutableBoxedArray
  , deepseqArray
  , deepseqArrayP
  , castBoxedArrayToVector
  , vectorToArray
  , castVectorToArray
  ) where

import           Control.DeepSeq                     (NFData (..), deepseq)
import           Control.Monad.ST                    (runST)
import qualified Data.Foldable                       as F (Foldable (..))
import           Data.Massiv.Array.Delayed.Internal  (eq, ord)
import           Data.Massiv.Array.Manifest.Internal (M, toManifest)
import           Data.Massiv.Array.Manifest.List     as L
import           Data.Massiv.Array.Mutable
import           Data.Massiv.Array.Ops.Fold.Internal
import           Data.Massiv.Array.Unsafe            (unsafeGenerateArray,
                                                      unsafeGenerateArrayP)
import           Data.Massiv.Core.Common
import           Data.Massiv.Core.List
import           Data.Massiv.Core.Scheduler
import qualified Data.Primitive.Array                as A
import qualified Data.Vector                         as VB
import qualified Data.Vector.Mutable                 as VB
import           GHC.Base                            (build)
import           GHC.Exts                            as GHC (IsList (..))
import           GHC.Prim
import           GHC.Types
import           Prelude                             hiding (mapM)
import           System.IO.Unsafe                    (unsafePerformIO)

#include "massiv.h"

sizeofArray :: A.Array e -> Int
sizeofMutableArray :: A.MutableArray s e -> Int
#if MIN_VERSION_primitive(0,6,2)
sizeofArray = A.sizeofArray
sizeofMutableArray = A.sizeofMutableArray
#else
sizeofArray (A.Array a#) = I# (sizeofArray# a#)
sizeofMutableArray (A.MutableArray ma#) = I# (sizeofMutableArray# ma#)
#endif

------------------
-- Boxed Strict --
------------------

-- | Array representation for Boxed elements. This structure is element and
-- spine strict, but elements are strict to Weak Head Normal Form (WHNF) only.
data B = B deriving Show

type instance EltRepr B ix = M

data instance Array B ix e = BArray { bComp :: !Comp
                                    , bSize :: !ix
                                    , bData :: {-# UNPACK #-} !(A.Array e)
                                    }

instance (Index ix, NFData e) => NFData (Array B ix e) where
  rnf (BArray comp sz arr) =
    case comp of
      Seq        -> deepseqArray sz arr ()
      ParOn wIds -> deepseqArrayP wIds sz arr ()

instance (Index ix, Eq e) => Eq (Array B ix e) where
  (==) = eq (==)
  {-# INLINE (==) #-}

instance (Index ix, Ord e) => Ord (Array B ix e) where
  compare = ord compare
  {-# INLINE compare #-}

instance Index ix => Construct B ix e where
  getComp = bComp
  {-# INLINE getComp #-}

  setComp c arr = arr { bComp = c }
  {-# INLINE setComp #-}

  unsafeMakeArray Seq          !sz f = unsafeGenerateArray sz f
  unsafeMakeArray (ParOn wIds) !sz f = unsafeGenerateArrayP wIds sz f
  {-# INLINE unsafeMakeArray #-}

instance Index ix => Source B ix e where
  unsafeLinearIndex (BArray _ _ a) =
    INDEX_CHECK("(Source B ix e).unsafeLinearIndex", sizeofArray, A.indexArray) a
  {-# INLINE unsafeLinearIndex #-}


instance Index ix => Size B ix e where
  size = bSize
  {-# INLINE size #-}

  unsafeResize !sz !arr = arr { bSize = sz }
  {-# INLINE unsafeResize #-}

  unsafeExtract !sIx !newSz !arr = unsafeExtract sIx newSz (toManifest arr)
  {-# INLINE unsafeExtract #-}


instance ( NFData e
         , Index ix
         , Index (Lower ix)
         , Elt M ix e ~ Array M (Lower ix) e
         , Elt B ix e ~ Array M (Lower ix) e
         ) =>
         OuterSlice B ix e where
  unsafeOuterSlice arr = unsafeOuterSlice (toManifest arr)
  {-# INLINE unsafeOuterSlice #-}

instance ( NFData e
         , Index ix
         , Index (Lower ix)
         , Elt M ix e ~ Array M (Lower ix) e
         , Elt B ix e ~ Array M (Lower ix) e
         ) =>
         InnerSlice B ix e where
  unsafeInnerSlice arr = unsafeInnerSlice (toManifest arr)
  {-# INLINE unsafeInnerSlice #-}


instance Index ix => Manifest B ix e where

  unsafeLinearIndexM (BArray _ _ a) =
    INDEX_CHECK("(Manifest B ix e).unsafeLinearIndexM", sizeofArray, A.indexArray) a
  {-# INLINE unsafeLinearIndexM #-}


instance Index ix => Mutable B ix e where
  data MArray s B ix e = MBArray !ix {-# UNPACK #-} !(A.MutableArray s e)

  msize (MBArray sz _) = sz
  {-# INLINE msize #-}

  unsafeThaw (BArray _ sz a) = MBArray sz <$> A.unsafeThawArray a
  {-# INLINE unsafeThaw #-}

  unsafeFreeze comp (MBArray sz ma) = BArray comp sz <$> A.unsafeFreezeArray ma
  {-# INLINE unsafeFreeze #-}

  unsafeNew sz = MBArray sz <$> A.newArray (totalElem sz) uninitialized
  {-# INLINE unsafeNew #-}

  unsafeNewZero = unsafeNew
  {-# INLINE unsafeNewZero #-}

  unsafeLinearRead (MBArray _ ma) =
    INDEX_CHECK("(Mutable B ix e).unsafeLinearRead", sizeofMutableArray, A.readArray) ma
  {-# INLINE unsafeLinearRead #-}

  unsafeLinearWrite (MBArray _ ma) i e = e `seq`
    INDEX_CHECK("(Mutable B ix e).unsafeLinearWrite", sizeofMutableArray, A.writeArray) ma i e
  {-# INLINE unsafeLinearWrite #-}


-- | Row-major sequential folding over a Boxed array.
instance Index ix => Foldable (Array B ix) where
  foldl = lazyFoldlS
  {-# INLINE foldl #-}
  foldl' = foldlS
  {-# INLINE foldl' #-}
  foldr = foldrFB
  {-# INLINE foldr #-}
  foldr' = foldrS
  {-# INLINE foldr' #-}
  null (BArray _ sz _) = totalElem sz == 0
  {-# INLINE null #-}
  sum = F.foldl' (+) 0
  {-# INLINE sum #-}
  product = F.foldl' (*) 1
  {-# INLINE product #-}
  length = totalElem . size
  {-# INLINE length #-}
  toList arr = build (\ c n -> foldrFB c n arr)
  {-# INLINE toList #-}


instance ( IsList (Array L ix e)
         , Nested LN ix e
         , Nested L ix e
         , Ragged L ix e
         ) =>
         IsList (Array B ix e) where
  type Item (Array B ix e) = Item (Array L ix e)
  fromList = L.fromLists' Seq
  {-# INLINE fromList #-}
  toList = GHC.toList . toListArray
  {-# INLINE toList #-}

-----------------------
-- Boxed Normal Form --
-----------------------

-- | Array representation for Boxed elements. This structure is element and
-- spine strict, and elements are always in Normal Form (NF), therefore `NFData`
-- instance is required.
data N = N deriving Show

type instance EltRepr N ix = M

newtype instance Array N ix e = NArray { bArray :: Array B ix e }

instance (Index ix, NFData e) => NFData (Array N ix e) where
  rnf (NArray (BArray comp sz arr)) =
    case comp of
      Seq        -> deepseqArray sz arr ()
      ParOn wIds -> deepseqArrayP wIds sz arr ()




instance (Index ix, NFData e, Eq e) => Eq (Array N ix e) where
  (==) = eq (==)
  {-# INLINE (==) #-}

instance (Index ix, NFData e, Ord e) => Ord (Array N ix e) where
  compare = ord compare
  {-# INLINE compare #-}


instance (Index ix, NFData e) => Construct N ix e where
  getComp = bComp . bArray
  {-# INLINE getComp #-}

  setComp c (NArray arr) = NArray (arr { bComp = c })
  {-# INLINE setComp #-}

  unsafeMakeArray Seq          !sz f = NArray $ unsafeGenerateArray sz f
  unsafeMakeArray (ParOn wIds) !sz f = NArray $ unsafeGenerateArrayP wIds sz f
  {-# INLINE unsafeMakeArray #-}

instance (Index ix, NFData e) => Source N ix e where
  unsafeLinearIndex (NArray arr) =
    INDEX_CHECK("(Source N ix e).unsafeLinearIndex", totalElem . size, unsafeLinearIndex) arr
  {-# INLINE unsafeLinearIndex #-}


instance (Index ix, NFData e) => Size N ix e where
  size = bSize . bArray
  {-# INLINE size #-}

  unsafeResize !sz = NArray . unsafeResize sz . bArray
  {-# INLINE unsafeResize #-}

  unsafeExtract !sIx !newSz !arr = unsafeExtract sIx newSz (toManifest arr)
  {-# INLINE unsafeExtract #-}


instance ( NFData e
         , Index ix
         , Index (Lower ix)
         , Elt M ix e ~ Array M (Lower ix) e
         , Elt N ix e ~ Array M (Lower ix) e
         ) =>
         OuterSlice N ix e where
  unsafeOuterSlice = unsafeOuterSlice . toManifest
  {-# INLINE unsafeOuterSlice #-}

instance ( NFData e
         , Index ix
         , Index (Lower ix)
         , Elt M ix e ~ Array M (Lower ix) e
         , Elt N ix e ~ Array M (Lower ix) e
         ) =>
         InnerSlice N ix e where
  unsafeInnerSlice = unsafeInnerSlice . toManifest
  {-# INLINE unsafeInnerSlice #-}


instance (Index ix, NFData e) => Manifest N ix e where

  unsafeLinearIndexM (NArray arr) =
    INDEX_CHECK("(Manifest N ix e).unsafeLinearIndexM", totalElem . size, unsafeLinearIndexM) arr
  {-# INLINE unsafeLinearIndexM #-}


instance (Index ix, NFData e) => Mutable N ix e where
  newtype MArray s N ix e = MNArray { bmArray :: MArray s B ix e }

  msize = msize . bmArray
  {-# INLINE msize #-}

  unsafeThaw (NArray arr) = MNArray <$> unsafeThaw arr
  {-# INLINE unsafeThaw #-}

  unsafeFreeze comp (MNArray marr) = NArray <$> unsafeFreeze comp marr
  {-# INLINE unsafeFreeze #-}

  unsafeNew sz = MNArray <$> unsafeNew sz
  {-# INLINE unsafeNew #-}

  unsafeNewZero = unsafeNew
  {-# INLINE unsafeNewZero #-}

  unsafeLinearRead (MNArray ma) =
    INDEX_CHECK("(Mutable N ix e).unsafeLinearRead", (totalElem . msize), unsafeLinearRead) ma
  {-# INLINE unsafeLinearRead #-}

  unsafeLinearWrite (MNArray ma) i e = e `deepseq`
    INDEX_CHECK("(Mutable N ix e).unsafeLinearWrite", (totalElem . msize), unsafeLinearWrite) ma i e
  {-# INLINE unsafeLinearWrite #-}


instance ( NFData e
         , IsList (Array L ix e)
         , Nested LN ix e
         , Nested L ix e
         , Ragged L ix e
         ) =>
         IsList (Array N ix e) where
  type Item (Array N ix e) = Item (Array L ix e)
  fromList = L.fromLists' Seq
  {-# INLINE fromList #-}
  toList = GHC.toList . toListArray
  {-# INLINE toList #-}


----------------------
-- Helper functions --
----------------------

uninitialized :: a
uninitialized = error "Data.Array.Massiv.Manifest.Boxed: uninitialized element"


toBoxedArray :: Array B ix e -> A.Array e
toBoxedArray = bData
{-# INLINE toBoxedArray #-}


fromBoxedArray :: Index ix => Comp -> ix -> A.Array e -> Maybe (Array B ix e)
fromBoxedArray comp sz barr
  | totalElem sz == sizeofArray barr = Just $ BArray comp sz barr
  | otherwise = Nothing
{-# INLINE fromBoxedArray #-}

-- | /O(1) - Unwrap mutable boxed array
toMutableBoxedArray :: MArray s B ix e -> A.MutableArray s e
toMutableBoxedArray (MBArray _ marr) = marr
{-# INLINE toMutableBoxedArray #-}


-- | /O(1) - Wrap mutable boxed array
fromMutableBoxedArray :: Index ix => ix -> A.MutableArray s e -> Maybe (MArray s B ix e)
fromMutableBoxedArray sz barr
  | totalElem sz == sizeofMutableArray barr = Just $ MBArray sz barr
  | otherwise = Nothing
{-# INLINE fromMutableBoxedArray #-}


deepseqArray :: (Index ix, NFData e) => ix -> A.Array e -> b -> b
deepseqArray sz arr b =
  iter 0 (totalElem sz) 1 (<) b $ \ !i acc -> A.indexArray arr i `deepseq` acc
{-# INLINE deepseqArray #-}


deepseqArrayP :: (Index ix, NFData e) => [Int] -> ix -> A.Array e -> b -> b
deepseqArrayP wIds sz arr b =
  unsafePerformIO $ do
    divideWork_ wIds sz $ \ !scheduler !chunkLength !totalLength !slackStart -> do
      loopM_ 0 (< slackStart) (+ chunkLength) $ \ !start ->
        scheduleWork scheduler $
        loopM_ start (< (start + chunkLength)) (+ 1) $ \ !k ->
          A.indexArray arr k `deepseq` return ()
      scheduleWork scheduler $
        loopM_ slackStart (< totalLength) (+ 1) $ \ !k ->
          A.indexArray arr k `deepseq` return ()
    return b
{-# INLINE deepseqArrayP #-}

-- | Helper function that converts a boxed `A.Array` into a `VB.Vector`. Supplied total number of
-- elements is assumed to be the same in the array as provided by the size.
castBoxedArrayToVector :: A.Array a -> VB.Vector a
castBoxedArrayToVector arr = runST $ do
  marr <- A.unsafeThawArray arr
  VB.unsafeFreeze $ VB.MVector 0 (sizeofArray arr) marr
{-# INLINE castBoxedArrayToVector #-}

-- | Covert boxed `VB.Vector` into an `A.Array`. Sliced vectors will indure copying.
vectorToArray :: VB.Vector a -> A.Array a
vectorToArray v =
  runST $ do
    VB.MVector start len marr <- VB.unsafeThaw v
    marr' <-
      if start == 0
        then return marr
        else A.cloneMutableArray marr start len
    A.unsafeFreezeArray marr'
{-# INLINE vectorToArray #-}


-- | Cast a Boxed Vector into an Array, but only if it wasn't previously sliced.
castVectorToArray :: VB.Vector a -> Maybe (A.Array a)
castVectorToArray v =
  runST $ do
    VB.MVector start _ marr <- VB.unsafeThaw v
    if start == 0
      then Just <$> A.unsafeFreezeArray marr
      else return Nothing
{-# INLINE castVectorToArray #-}