{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
-- |
-- Module      : Data.Massiv.Array.Manifest
-- Copyright   : (c) Alexey Kuleshevich 2017
-- License     : BSD3
-- Maintainer  : Alexey Kuleshevich <lehins@yandex.ru>
-- Stability   : experimental
-- Portability : non-portable
--
module Data.Massiv.Array.Manifest
  ( -- * Manifest
    Manifest
  , toManifest
  , M
  -- * Boxed
  , B(..)
  , N(..)
  -- * Primitive
  , P(..)
  , Prim
  -- * Storable
  , S(..)
  , Storable
  -- * Unboxed
  , U(..)
  , Unbox
  -- * Conversion
  -- ** List
  , fromList
  , fromList'
  , toList
  -- ** Vector
  , fromVector
  , castFromVector
  , toVector
  , castToVector
  , ARepr
  , VRepr
  -- * Indexing
  , (!)
  , index
  , (!?)
  , maybeIndex
  , (?)
  , defaultIndex
  , borderIndex
  ) where

import           Control.Monad                        (guard, join, msum)
import           Data.Massiv.Core
import           Data.Massiv.Core.List
import           Data.Massiv.Array.Manifest.BoxedStrict
import           Data.Massiv.Array.Manifest.BoxedNF
import           Data.Massiv.Array.Manifest.Internal
import           Data.Massiv.Array.Manifest.Primitive
import           Data.Massiv.Array.Manifest.Storable
import           Data.Massiv.Array.Manifest.Unboxed
import           Data.Massiv.Array.Mutable
import           Data.Typeable
import qualified Data.Vector                          as VB
import qualified Data.Vector.Generic                  as VG
import qualified Data.Vector.Primitive                as VP
import qualified Data.Vector.Storable                 as VS
import qualified Data.Vector.Unboxed                  as VU

type family ARepr (v :: * -> *) :: *
type family VRepr r :: * -> *

type instance ARepr VU.Vector = U
type instance ARepr VS.Vector = S
type instance ARepr VP.Vector = P
type instance ARepr VB.Vector = B
type instance VRepr U = VU.Vector
type instance VRepr S = VS.Vector
type instance VRepr P = VP.Vector
type instance VRepr B = VB.Vector
type instance VRepr N = VB.Vector

infixl 4 !, !?, ?

-- | Infix version of `index`.
(!) :: Manifest r ix e => Array r ix e -> ix -> e
(!) = index
{-# INLINE (!) #-}


-- | Infix version of `maybeIndex`.
(!?) :: Manifest r ix e => Array r ix e -> ix -> Maybe e
(!?) = maybeIndex
{-# INLINE (!?) #-}


(?) :: Manifest r ix e => Maybe (Array r ix e) -> ix -> Maybe e
(?) Nothing    = const Nothing
(?) (Just arr) = (arr !?)
{-# INLINE (?) #-}


maybeIndex :: Manifest r ix e => Array r ix e -> ix -> Maybe e
maybeIndex arr = handleBorderIndex (Fill Nothing) (size arr) (Just . unsafeIndex arr)
{-# INLINE maybeIndex #-}


defaultIndex :: Manifest r ix e => e -> Array r ix e -> ix -> e
defaultIndex defVal = borderIndex (Fill defVal)
{-# INLINE defaultIndex #-}


borderIndex :: Manifest r ix e => Border e -> Array r ix e -> ix -> e
borderIndex border arr = handleBorderIndex border (size arr) (unsafeIndex arr)
{-# INLINE borderIndex #-}


index :: Manifest r ix e => Array r ix e -> ix -> e
index arr ix = borderIndex (Fill (errorIx "index" (size arr) ix)) arr ix
{-# INLINE index #-}

-- | /O(1)/ conversion from vector to an array with a corresponding
-- representation. Will return `Nothing` if there is a size mismatch, vector has
-- been sliced before or if some non-standard vector type is supplied.
castFromVector :: forall v r ix e. (VG.Vector v e, Typeable v, Mutable r ix e, ARepr v ~ r)
               => Comp
               -> ix -- ^ Size of the result Array
               -> v e -- ^ Source Vector
               -> Maybe (Array r ix e)
castFromVector comp sz vector = do
  guard (totalElem sz == VG.length vector)
  msum
    [ do Refl <- eqT :: Maybe (v :~: VU.Vector)
         uVector <- join $ gcast1 (Just vector)
         return $ UArray {uComp = comp, uSize = sz, uData = uVector}
    , do Refl <- eqT :: Maybe (v :~: VS.Vector)
         sVector <- join $ gcast1 (Just vector)
         return $ SArray {sComp = comp, sSize = sz, sData = sVector}
    , do Refl <- eqT :: Maybe (v :~: VP.Vector)
         VP.Vector 0 _ arr <- join $ gcast1 (Just vector)
         return $ PArray {pComp = comp, pSize = sz, pData = arr}
    , do Refl <- eqT :: Maybe (v :~: VB.Vector)
         bVector <- join $ gcast1 (Just vector)
         arr <- castVectorToArray bVector
         return $ BArray {bComp = comp, bSize = sz, bData = arr}
    ]
{-# INLINE castFromVector #-}


-- | In case when resulting array representation matches the one of vector's it
-- will do a /O(1)/ conversion using `castFromVector`, otherwise Vector elements
-- will be copied into a new array. Will throw an error if length of resulting
-- array doesn't match the source vector length.
fromVector ::
     (Typeable v, VG.Vector v a, Mutable (ARepr v) ix a, Mutable r ix a)
  => Comp
  -> ix -- ^ Resulting size of the array
  -> v a -- ^ Source Vector
  -> Array r ix a
fromVector comp sz v =
  case castFromVector comp sz v of
    Just arr -> convert arr
    Nothing ->
      if (totalElem sz /= VG.length v)
        then error $
             "Data.Array.Massiv.Manifest.fromVector: Supplied size: " ++
             show sz ++ " doesn't match vector length: " ++ show (VG.length v)
        else unsafeMakeArray comp sz ((v VG.!) . toLinearIndex sz)
{-# INLINE fromVector #-}


-- | /O(1)/ conversion from `Mutable` array to a corresponding vector. Will
-- return `Nothing` only if source array representation was not one of `B`, `N`,
-- `P`, `S` or `U`.
castToVector :: forall v r ix e . (VG.Vector v e, Mutable r ix e, VRepr r ~ v)
         => Array r ix e -> Maybe (v e)
castToVector arr =
  msum
    [ do Refl <- eqT :: Maybe (r :~: U)
         uArr <- gcastArr arr
         return $ uData uArr
    , do Refl <- eqT :: Maybe (r :~: S)
         sArr <- gcastArr arr
         return $ sData sArr
    , do Refl <- eqT :: Maybe (r :~: P)
         pArr <- gcastArr arr
         return $ VP.Vector 0 (totalElem (size arr)) $ pData pArr
    , do Refl <- eqT :: Maybe (r :~: B)
         bArr <- gcastArr arr
         return $ vectorFromArray (size arr) $ bData bArr
    , do Refl <- eqT :: Maybe (r :~: N)
         bArr <- gcastArr arr
         return $ vectorFromArray (size arr) $ nData bArr
    ]
{-# INLINE castToVector #-}


-- | Convert an array into a vector. Will perform a cast if resulting vector is
-- of compatible representation, otherwise memory copy will occur.
--
-- ==== __Examples__
--
-- In this example a `S`torable Array is created and then casted into a Storable
-- `VS.Vector` in costant time:
--
-- >>> import qualified Data.Vector.Storable as VS
-- >>> toVector (makeArrayR S Par (5 :. 6) (\(i :. j) -> i + j)) :: VS.Vector Int
-- [0,1,2,3,4,5,1,2,3,4,5,6,2,3,4,5,6,7,3,4,5,6,7,8,4,5,6,7,8,9]
--
-- While in this example `S`torable Array will first be converted into `U`nboxed
-- representation in `Par`allel and only after that will be coverted into Unboxed
-- `VU.Vector` in constant time.
--
-- >>> import qualified Data.Vector.Unboxed as VU
-- >>> toVector (makeArrayR S Par (5 :. 6) (\(i :. j) -> i + j)) :: VU.Vector Int
-- [0,1,2,3,4,5,1,2,3,4,5,6,2,3,4,5,6,7,3,4,5,6,7,8,4,5,6,7,8,9]
--
toVector ::
     forall r ix e v.
     ( Manifest r ix e
     , Mutable (ARepr v) ix e
     , VG.Vector v e
     , VRepr (ARepr v) ~ v
     )
  => Array r ix e
  -> v e
toVector arr =
  case castToVector (convert arr :: Array (ARepr v) ix e) of
    Just v -> v
    Nothing -> VG.generate (totalElem (size arr)) (unsafeLinearIndex arr)
{-# INLINE toVector #-}


-- | Juts like `fromList'`, but will return `Nothing` instead of throwing an
-- error on irregular shaped lists.
fromList :: (Nested LN ix e, Nested L ix e, Ragged L ix e, Mutable r ix e)
         => Comp -- ^ Computation startegy to use
         -> [ListItem ix e] -- ^ Nested list
         -> Maybe (Array r ix e)
fromList comp = either (const Nothing) Just . fromRaggedArray . setComp comp . throughNested
{-# INLINE fromList #-}

-- | Convert a nested list into an array. Nested list must be of a rectangular
-- shape, otherwise a runtime error will occur. Also, nestedness must match the
-- dimensionality of resulting array, which must be specified through an
-- explicit type signature.
--
-- ==== __Examples__
--
-- >>> fromList' Seq [[1,2],[3,4]] :: Array U Ix2 Int
-- (Array U Seq (2 :. 2)
-- [ [ 1,2 ]
-- , [ 3,4 ]
-- ])
--
-- >>> fromList' Par [[[1,2,3]],[[4,5,6]]] :: Array U Ix3 Int
-- (Array U Par (2 :> 1 :. 3)
-- [ [ [ 1,2,3 ]
--   ]
-- , [ [ 4,5,6 ]
--   ]
-- ])
--
-- Elements of a boxed array could be lists themselves if necessary:
--
-- >>> fromList' Seq [[[1,2,3]],[[4,5]]] :: Array B Ix2 [Int]
-- (Array B Seq (2 :. 1)
-- [ [ [1,2,3] ]
-- , [ [4,5] ]
-- ])
--
fromList' :: (Nested LN ix e, Nested L ix e, Ragged L ix e, Mutable r ix e)
         => Comp -- ^ Computation startegy to use
         -> [ListItem ix e] -- ^ Nested list
         -> Array r ix e
fromList' comp = fromRaggedArray' . setComp comp . throughNested
{-# INLINE fromList' #-}


throughNested :: forall ix e . (Nested LN ix e, Nested L ix e) => [ListItem ix e] -> Array L ix e
throughNested xs = fromNested (fromNested xs :: Array LN ix e)
{-# INLINE throughNested #-}


-- | Convert an array into a nested list.
--
-- ====__Examples__
--
-- >>> makeArrayR U Seq (2 :> 1 :. 3) fromIx3
-- (Array U Seq (2 :> 1 :. 3)
-- [ [ [ (0,0,0),(0,0,1),(0,0,2) ]
--   ]
-- , [ [ (1,0,0),(1,0,1),(1,0,2) ]
--   ]
-- ])
-- >>> toList $ makeArrayR U Seq (2 :> 1 :. 3) fromIx3
-- [[[(0,0,0),(0,0,1),(0,0,2)]],[[(1,0,0),(1,0,1),(1,0,2)]]]
--
toList :: (Nested LN ix e, Nested L ix e, Construct L ix e, Source r ix e)
       => Array r ix e
       -> [ListItem ix e]
toList = toNested . toNested . toListArray
{-# INLINE toList #-}
