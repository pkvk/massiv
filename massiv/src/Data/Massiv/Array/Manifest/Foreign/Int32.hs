{-# LANGUAGE BangPatterns          #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE UndecidableInstances  #-}
-- |
-- Module      : Data.Massiv.Array.Manifest.Foreign.Int32
-- Copyright   : (c) Alexey Kuleshevich 2018
-- License     : BSD3
-- Maintainer  : Alexey Kuleshevich <lehins@yandex.ru>
-- Stability   : experimental
-- Portability : non-portable
--
module Data.Massiv.Array.Manifest.Foreign.Int32 where

import Control.Monad
import Data.Int
import Data.Massiv.Array.Manifest.Foreign.Internal
import Data.Massiv.Array.Manifest.Internal
import Data.Massiv.Array.Mutable
import Data.Massiv.Array.Unsafe (unsafeGenerateArray, unsafeGenerateArrayP)
import Data.Massiv.Core.Common
import Data.Massiv.Core.Scheduler
import Data.Monoid
import Foreign.Ptr
import Prelude hiding (mapM)
import System.IO.Unsafe
import Control.DeepSeq

instance (Index ix, NFData e) => NFData (Array F ix e) where
  rnf (FArray c v) = c `deepseq` v `seq` ()

-- instance (VS.Storable e, Eq e, Index ix) => Eq (Array S ix e) where
--   (==) = eq (==)
--   {-# INLINE (==) #-}

-- instance (VS.Storable e, Ord e, Index ix) => Ord (Array S ix e) where
--   compare = ord compare
--   {-# INLINE compare #-}

data T a b = !a :- !b

instance (Index ix, Mutable F ix e) => Construct F ix e where
  getComp = fComp
  {-# INLINE getComp #-}

  setComp c arr = arr { fComp = c }
  {-# INLINE setComp #-}

  unsafeMakeArray Seq          !sz f = unsafeGenerateArray sz f
  unsafeMakeArray (ParOn wIds) !sz f = unsafeGenerateArrayP wIds sz f
  {-# INLINE unsafeMakeArray #-}


instance (Index ix, Mutable F ix e) => Source F ix e where
  unsafeLinearIndex = fUnsafeLinearIndex
  {-# INLINE unsafeLinearIndex #-}


instance (Index ix, Mutable F ix e) => Size F ix e where
  size = msize . fMArray
  {-# INLINE size #-}
  unsafeResize !sz (FArray c mfa) = FArray c $ unsafeSetSize mfa sz
  unsafeExtract !sIx !newSz !arr = unsafeExtract sIx newSz (toManifest arr)
  {-# INLINE unsafeExtract #-}



-- instance ( VS.Storable e
--          , Index ix
--          , Index (Lower ix)
--          , Elt M ix e ~ Array M (Lower ix) e
--          , Elt S ix e ~ Array M (Lower ix) e
--          ) =>
--          OuterSlice S ix e where
--   unsafeOuterSlice arr = unsafeOuterSlice (toManifest arr)
--   {-# INLINE unsafeOuterSlice #-}

-- instance ( VS.Storable e
--          , Index ix
--          , Index (Lower ix)
--          , Elt M ix e ~ Array M (Lower ix) e
--          , Elt S ix e ~ Array M (Lower ix) e
--          ) =>
--          InnerSlice S ix e where
--   unsafeInnerSlice arr = unsafeInnerSlice (toManifest arr)
--   {-# INLINE unsafeInnerSlice #-}


instance (Index ix, Mutable F ix e) => Manifest F ix e where
  unsafeLinearIndexM = fUnsafeLinearIndex
  {-# INLINE unsafeLinearIndexM #-}



instance Index ix => Mutable F ix Int32 where
  data MArray s F ix Int32 = MFArrayInt32 !ix !(ArrayPtr Int32)

  msize (MFArrayInt32 sz _) = sz
  {-# INLINE msize #-}

  unsafeSetSize (MFArrayInt32 _ mf) sz = MFArrayInt32 sz mf
  {-# INLINE unsafeSetSize #-}

  unsafeThaw (FArray _ (MFArrayInt32 sz mf)) = return (MFArrayInt32 sz mf)
  {-# INLINE unsafeThaw #-}

  unsafeFreeze comp (MFArrayInt32 sz fp) = return (FArray comp (MFArrayInt32 sz fp))
  {-# INLINE unsafeFreeze #-}

  unsafeNew sz = MFArrayInt32 sz <$> mfUnsafeNew sz
  {-# INLINE unsafeNew #-}

  unsafeNewZero = unsafeNew
  {-# INLINE unsafeNewZero #-}

  unsafeLinearRead (MFArrayInt32 _ mf) = mfUnsafeLinearRead mf
  {-# INLINE unsafeLinearRead #-}

  unsafeLinearWrite (MFArrayInt32 _ mf) = mfUnsafeLinearWrite mf
  {-# INLINE unsafeLinearWrite #-}


instance (Index ix, Mutable F ix a, Mutable F ix b) => Mutable F ix (a, b) where
  data MArray s F ix (a, b) = MFArrayT !ix !(T (MArray s F ix a) (MArray s F ix b))

  msize (MFArrayT sz _) = sz
  {-# INLINE msize #-}

  unsafeSetSize (MFArrayT _ (mfa :- mfb)) sz =
    MFArrayT sz (unsafeSetSize mfa sz :- unsafeSetSize mfb sz)
  {-# INLINE unsafeSetSize #-}

  unsafeThaw (FArray c (MFArrayT sz (mfa :- mfb))) = do
    mfa' <- unsafeThaw (FArray c mfa)
    mfb' <- unsafeThaw (FArray c mfb)
    return (MFArrayT sz (mfa' :- mfb'))
  {-# INLINE unsafeThaw #-}

  unsafeFreeze comp (MFArrayT sz (mfa :- mfb)) = do
    FArray _ mfa' <- unsafeFreeze comp mfa
    FArray _ mfb' <- unsafeFreeze comp mfb
    return (FArray comp (MFArrayT sz (mfa' :- mfb')))
  {-# INLINE unsafeFreeze #-}

  unsafeNew sz = do
    a <- unsafeNew sz
    b <- unsafeNew sz
    return $ MFArrayT sz (a :- b)
  {-# INLINE unsafeNew #-}

  unsafeNewZero = unsafeNew
  {-# INLINE unsafeNewZero #-}

  unsafeLinearRead (MFArrayT _ (mfa :- mfb)) i = do
    a <- unsafeLinearRead mfa i
    b <- unsafeLinearRead mfb i
    return (a, b)
  {-# INLINE unsafeLinearRead #-}

  unsafeLinearWrite (MFArrayT _ (mfa :- mfb)) i (a, b) = do
    unsafeLinearWrite mfa i a
    unsafeLinearWrite mfb i b
  {-# INLINE unsafeLinearWrite #-}


instance {-# OVERLAPPABLE #-}  (Mutable F ix e, Num e) => Num (Array F ix e) where
  (+) (FArray ca fa) (FArray cb fb) = unsafePerformIO $ do
    let sz = msize fa
    fc <- unsafeNew sz
    loopM_ 0 (< totalElem sz) (+1) $ \i -> do
      a <- unsafeLinearRead fa i
      b <- unsafeLinearRead fb i
      unsafeLinearWrite fc i (a + b)
    unsafeFreeze (ca <> cb) fc


-- instance {-# OVERLAPPING #-} Index ix => Num (Array F ix Int32) where
--   (+) (FArray ca fa) (FArray cb fb) = unsafePerformIO $ do


-- plusF ::
--      (Mutable F ix e, Mutable F ix e, Num e)
--   => Array F ix e
--   -> Array F ix e
--   -> Array F ix e
-- plusF (FArray ca fa) (FArray cb fb) =
--   unsafePerformIO $ do
--     let sz = msize fa
--     fc <- unsafeNew sz
--     loopM_ 0 (< totalElem sz) (+ 1) $ \i -> do
--       a <- unsafeLinearRead fa i
--       b <- unsafeLinearRead fb i
--       unsafeLinearWrite fc i (a + b)
--     unsafeFreeze (ca <> cb) fc
-- {-# INLINE plusF #-}

plusF :: Index ix => Array F ix Int32 -> Array F ix Int32 -> Array F ix Int32
plusF (FArray ca fa) (FArray cb fb) =
  unsafePerformIO $ do
    let sz = msize fa
    fc <- unsafeNew sz
    loopM_ 0 (< totalElem sz) (+ 1) $ \i -> do
      a <- unsafeLinearRead fa i
      b <- unsafeLinearRead fb i
      unsafeLinearWrite fc i (a + b)
    unsafeFreeze (ca <> cb) fc
{-# INLINE plusF #-}


plusSimpleInt32 :: Index ix => Array F ix Int32 -> Array F ix Int32 -> Array F ix Int32
plusSimpleInt32 (FArray ca (MFArrayInt32 sz ma)) (FArray cb (MFArrayInt32 sz' mb)) = do
  unsafePerformIO $ do
    guard (sz == sz')
    let n = totalElem sz
    marr@(MFArrayInt32 _ mr) <- unsafeNew sz
    withArrayPtr mr $ \vr -> do
      withArrayPtr ma $ \va -> do
        withArrayPtr mb $ \vb -> do
          add_i32_simple vr va vb n
    unsafeFreeze (ca <> cb) marr
{-# INLINE plusSimpleInt32 #-}


plusInt32 :: Index ix => Array F ix Int32 -> Array F ix Int32 -> Array F ix Int32
plusInt32 (FArray ca (MFArrayInt32 sz ma)) (FArray cb (MFArrayInt32 sz' mb)) = do
  unsafePerformIO $ do
    --guard (sz == sz')
    let n = totalElem sz
    marr@(MFArrayInt32 _ mr) <- unsafeNew sz
    let vn = n `div` 4
    withArrayPtr mr $ \vr -> do
      withArrayPtr ma $ \va -> do
        withArrayPtr mb $ \vb -> do
          add_i32 vr va vb vn
    -- loopM_ vn (< n) (+ 1) $ \i -> do
    --   a <- mfUnsafeLinearRead ma i
    --   b <- mfUnsafeLinearRead mb i
    --   mfUnsafeLinearWrite mr i (a + b)
    unsafeFreeze (ca <> cb) marr
{-# INLINE plusInt32 #-}


plusSeqInt32 :: Index ix => Array F ix Int32 -> Array F ix Int32 -> Array F ix Int32
plusSeqInt32 (FArray ca (MFArrayInt32 sz ma)) (FArray cb (MFArrayInt32 sz' mb)) = do
  unsafePerformIO $ do
    guard (sz == sz')
    marr@(MFArrayInt32 _ mr) <- unsafeNew sz
    withArrayPtr mr $ \ !vr -> do
      withArrayPtr ma $ \ !va -> do
        withArrayPtr mb $ \ !vb -> do
          add_i32_full vr va vb (totalElem sz)
    unsafeFreeze (ca  <> cb) marr
{-# INLINE plusSeqInt32 #-}



plusParInt32 :: Index ix => Array F ix Int32 -> Array F ix Int32 -> Array F ix Int32
plusParInt32 (FArray ca (MFArrayInt32 sz ma)) (FArray cb (MFArrayInt32 sz' mb)) = do
  unsafePerformIO $ do
    guard (sz == sz')
    let n = totalElem sz
    marr@(MFArrayInt32 _ mr) <- unsafeNew sz
    withScheduler_ [] $ \scheduler -> do
      let vn = n `div` 4
          wn = numWorkers scheduler
      withArrayPtr mr $ \vr -> do
        withArrayPtr ma $ \va -> do
          withArrayPtr mb $ \vb -> do
            let perWorker = vn `div` wn
            loopM_ 0 (< wn) (+ 1) $ \w -> do
              scheduleWork scheduler $ do
                let shift = w * perWorker * 4 * 4
                add_i32 (plusPtr vr shift) (plusPtr va shift) (plusPtr vb shift) perWorker
      scheduleWork scheduler $ do
        loopM_ (vn * wn * 4) (< n) (+ 1) $ \i -> do
          a <- mfUnsafeLinearRead ma i
          b <- mfUnsafeLinearRead mb i
          mfUnsafeLinearWrite mr i (a + b)
    unsafeFreeze (ca <> cb) marr
{-# INLINE plusParInt32 #-}


foreign import ccall unsafe "add_i32" add_i32 ::
               Ptr Int32 -> Ptr Int32 -> Ptr Int32 -> Int -> IO ()

foreign import ccall unsafe "add_i32_alt" add_i32_alt ::
               Ptr Int32 -> Ptr Int32 -> Ptr Int32 -> Int -> IO ()

foreign import ccall unsafe "add_i32_simple" add_i32_simple ::
               Ptr Int32 -> Ptr Int32 -> Ptr Int32 -> Int -> IO ()

foreign import ccall unsafe "add_i32_full" add_i32_full ::
               Ptr Int32 -> Ptr Int32 -> Ptr Int32 -> Int -> IO ()




-- let a = (unsafeMakeArray Seq (12 :. 5) $ \(i :. j) -> fromIntegral (i*j)) :: Array F Ix2 Int32
