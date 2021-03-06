{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ExplicitForAll #-}
{-# LANGUAGE FlexibleContexts #-}
-- |
-- Module      : Data.Massiv.Array.Ops.Sort
-- Copyright   : (c) Alexey Kuleshevich 2018-2019
-- License     : BSD3
-- Maintainer  : Alexey Kuleshevich <lehins@yandex.ru>
-- Stability   : experimental
-- Portability : non-portable
--
module Data.Massiv.Array.Ops.Sort
  ( quicksort
  , quicksortM_
  , unsafeUnstablePartitionRegionM
  ) where

import Control.Monad (when)
import Control.Scheduler
import Data.Massiv.Array.Mutable
import Data.Massiv.Core.Common
import System.IO.Unsafe

-- | Partition a segment of a vector. Starting and ending indices are unchecked.
--
-- @since 0.3.2
unsafeUnstablePartitionRegionM ::
     forall r e m. (Mutable r Ix1 e, PrimMonad m)
  => MArray (PrimState m) r Ix1 e
  -> (e -> Bool)
  -> Ix1 -- ^ Start index of the region
  -> Ix1 -- ^ End index of the region
  -> m Ix1
unsafeUnstablePartitionRegionM marr f start end = fromLeft start (end + 1)
  where
    fromLeft i j
      | i == j = pure i
      | otherwise = do
        x <- unsafeRead marr i
        if f x
          then fromLeft (i + 1) j
          else fromRight i (j - 1)
    fromRight i j
      | i == j = pure i
      | otherwise = do
        x <- unsafeRead marr j
        if f x
          then do
            unsafeWrite marr j =<< unsafeRead marr i
            unsafeWrite marr i x
            fromLeft (i + 1) j
          else fromRight i (j - 1)
{-# INLINE unsafeUnstablePartitionRegionM #-}


-- | This is an implementation of [Quicksort](https://en.wikipedia.org/wiki/Quicksort), which is an
-- efficient, but unstable sort that uses Median-of-three for pivot choosing, as such it performs
-- very well not only for random values, but also for common edge cases like already sorted,
-- reversed sorted and arrays with many duplicate elements. It will also respect the computation
-- strategy and will result in a nice speed up for systems with multiple CPUs.
--
-- @since 0.3.2
quicksort ::
     (Mutable r Ix1 e, Ord e) => Array r Ix1 e -> Array r Ix1 e
quicksort arr =
  unsafePerformIO $
  withMArray arr (\n s -> quicksortM_ (trivialScheduler_ {numWorkers = n, scheduleWork = s}))
{-# INLINE quicksort #-}

-- | Mutable version of `quicksort`
--
-- @since 0.3.2
quicksortM_ ::
     (Ord e, Mutable r Ix1 e, PrimMonad m)
  => Scheduler m ()
  -> MArray (PrimState m) r Ix1 e
  -> m ()
quicksortM_ scheduler marr =
  scheduleWork scheduler $ qsort (numWorkers scheduler) 0 (unSz (msize marr) - 1)
  where
    leSwap i j = do
      ei <- unsafeRead marr i
      ej <- unsafeRead marr j
      if ei < ej
        then do
          unsafeWrite marr i ej
          unsafeWrite marr j ei
          pure ei
        else pure ej
    {-# INLINE leSwap #-}
    getPivot lo hi = do
      let !mid = (hi + lo) `div` 2
      _ <- leSwap mid lo
      _ <- leSwap hi lo
      leSwap mid hi
    {-# INLINE getPivot #-}
    qsort !n !lo !hi =
      when (lo < hi) $ do
        p <- getPivot lo hi
        l <- unsafeUnstablePartitionRegionM marr (< p) lo (hi - 1)
        h <- unsafeUnstablePartitionRegionM marr (== p) l hi
        if n > 0
          then do
            let !n' = n - 1
            scheduleWork scheduler $ qsort n' lo (l - 1)
            scheduleWork scheduler $ qsort n' h hi
          else do
            qsort n lo (l - 1)
            qsort n h hi
{-# INLINE quicksortM_ #-}
