{-# LANGUAGE CPP, GeneralizedNewtypeDeriving, TypeFamilies, OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances, Rank2Types #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Properties.Map
    where

import Control.Arrow ((***))
import Data.CritBit.Map.Lazy (CritBitKey, CritBit, byteCount)
import Data.Foldable (foldMap)
import Data.Function (on)
import Data.List (unfoldr, sort, nubBy)
import Data.Map (Map)
import Data.Monoid (Monoid, Sum(..))
import Data.String (IsString)
import Data.Word (Word8)
import Properties.Common
import Test.Framework (Test, testGroup)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.QuickCheck (Arbitrary)
import Test.QuickCheck.Property (Testable)
import qualified Data.ByteString.Char8 as B
import qualified Data.CritBit.Map.Lazy as C
import qualified Data.CritBit.Set as CSet
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as T

--only needed for a test requiring containers >= 0.5
#if MIN_VERSION_containers(0,5,0)
import Data.Functor.Identity (Identity(..))
#endif

type V = Word8
type KV k = [(k, V)]

type SA k = SameAs (CritBit k V) (Map k V) (KV k)

type CBProp           = (CritBitKey k, Ord k, Show k, IsString k, Monoid k)
                      => SA k -> KV k -> Bool
type WithKeyProp      = (CritBitKey k, Ord k, Show k, IsString k, Monoid k)
                      => SA k -> KV k -> k -> Bool
type WithKeyValueProp = (CritBitKey k, Ord k, Show k, IsString k, Monoid k)
                      => SA k -> KV k -> k -> V -> Bool
type WithMapProp      = (CritBitKey k, Ord k, Show k, IsString k, Monoid k)
                      => SA k -> KV k -> KV k -> Bool

presentMissingProperty :: (Eq k, Arbitrary k, Show k, IsString k, Testable t)
                       => String -> (SA k -> KV k -> k -> t) -> SA k -> [Test]
presentMissingProperty name t sa = [
    testProperty (name ++ "_general") $ general
  , testProperty (name ++ "_present") $ present
  , testProperty (name ++ "_missing") $ missing
  ]
  where
    general k   kvs = t sa kvs k
    present k v kvs = t sa ((k, v):kvs) k
    missing k   kvs = t sa (filter ((/= k) . fst) kvs) k

-- * Common modifier functions

kvvf :: (CritBitKey k) => k -> V -> V -> V
kvvf k v1 v2 = toEnum (byteCount k) * 3 + v1 * 2 - v2

kvvfm :: (CritBitKey k) => k -> V -> V -> Maybe V
kvvfm k v1 v2 = if even v1 then Just (kvvf k v1 v2) else Nothing

kvf :: (CritBitKey k) => k -> V -> V
kvf k v = kvvf k v 0

kvfm :: (CritBitKey k) => k -> V -> Maybe V
kvfm k v = kvvfm k v 0

vvfm :: V -> V -> Maybe V
vvfm = kvvfm ("" :: T.Text)

vfm :: V -> Maybe V
vfm = kvfm ("" :: T.Text)

-- * Test properties

t_null :: CBProp
t_null = C.null =*= Map.null

t_size :: CBProp
t_size = C.size =*= Map.size

t_lookup :: WithKeyProp
t_lookup = C.lookup =?*= Map.lookup

#if MIN_VERSION_containers(0,5,0)
t_lookupGT :: WithKeyProp
t_lookupGT = C.lookupGT =?*= Map.lookupGT

t_lookupGE :: WithKeyProp
t_lookupGE = C.lookupGE =?*= Map.lookupGE

t_lookupLT :: WithKeyProp
t_lookupLT = C.lookupLT =?*= Map.lookupLT

t_lookupLE :: WithKeyProp
t_lookupLE = C.lookupLE =?*= Map.lookupLE
#endif

t_fromList :: CBProp
t_fromList = C.fromList =?= Map.fromList

t_fromListWith :: CBProp
t_fromListWith = C.fromListWith (-) =?= Map.fromListWith (-)

t_fromListWithKey :: CBProp
t_fromListWithKey = C.fromListWithKey kvvf =?= Map.fromListWithKey kvvf

t_delete :: WithKeyProp
t_delete = C.delete =?*= Map.delete

t_adjust :: WithKeyProp
t_adjust = C.adjust (+3) =?*= Map.adjust (+3)

t_adjustWithKey :: WithKeyProp
t_adjustWithKey = C.adjustWithKey kvf =?*= Map.adjustWithKey kvf

t_updateLookupWithKey :: WithKeyProp
t_updateLookupWithKey = C.updateLookupWithKey kvfm =?*=
                      Map.updateLookupWithKey kvfm

t_update :: WithKeyProp
t_update = C.update vfm =?*= Map.update vfm

t_updateWithKey :: WithKeyProp
t_updateWithKey = C.updateWithKey kvfm =?*= Map.updateWithKey kvfm

t_mapMaybe :: CBProp
t_mapMaybe = C.mapMaybe vfm =*= Map.mapMaybe vfm

t_mapMaybeWithKey :: CBProp
t_mapMaybeWithKey = C.mapMaybeWithKey kvfm =*= Map.mapMaybeWithKey kvfm

t_mapEither :: CBProp
t_mapEither = (C.toList *** C.toList) . C.mapEither f =*=
              (Map.toList *** Map.toList) . Map.mapEither f
  where f x = if even x then Left (2 * x) else Right (3 * x)

t_mapEitherWithKey :: CBProp
t_mapEitherWithKey = (C.toList *** C.toList) . C.mapEitherWithKey f =*=
                     (Map.toList *** Map.toList) . Map.mapEitherWithKey f
  where f k x = if even x then Left (x + toEnum (C.byteCount k))
                          else Right (2 * x)

t_unionL :: WithMapProp
t_unionL = C.unionL =**= Map.union

t_unionR :: WithMapProp
t_unionR = C.unionR =**= flip Map.union

t_unionWith :: WithMapProp
t_unionWith = C.unionWith (-) =**= Map.unionWith (-)

t_unionWithKey :: WithMapProp
t_unionWithKey = C.unionWithKey kvvf =**= Map.unionWithKey kvvf

t_unions :: (CritBitKey k, Ord k) => SA k -> Small [KV k] -> Bool
t_unions = (C.unions . map C.fromList =*==
          Map.unions . map Map.fromList) fromSmall

t_unionsWith :: (CritBitKey k, Ord k) => SA k -> Small [KV k] -> Bool
t_unionsWith = (C.unionsWith (-) . map C.fromList =*==
              Map.unionsWith (-) . map Map.fromList) fromSmall

t_difference :: WithMapProp
t_difference = C.difference =**= Map.difference

t_differenceWith :: WithMapProp
t_differenceWith = C.differenceWith vvfm =**= Map.differenceWith vvfm

t_differenceWithKey :: WithMapProp
t_differenceWithKey = C.differenceWithKey kvvfm =**= Map.differenceWithKey kvvfm

t_intersection :: WithMapProp
t_intersection = C.intersection =**= Map.intersection

t_intersectionWith :: WithMapProp
t_intersectionWith = C.intersectionWith (-) =**= Map.intersectionWith (-)

t_intersectionWithKey :: WithMapProp
t_intersectionWithKey = C.intersectionWithKey kvvf =**=
                        Map.intersectionWithKey kvvf

t_foldl :: CBProp
t_foldl = C.foldl (-) 0 =*= Map.foldl (-) 0

t_foldlWithKey :: CBProp
t_foldlWithKey = C.foldlWithKey f ([], 0) =*= Map.foldlWithKey f ([], 0)
  where
    f (l,s) k v = (k:l,s+v)

t_foldl' :: CBProp
t_foldl' = C.foldl' (-) 0 =*= Map.foldl' (-) 0

t_foldlWithKey' :: CBProp
t_foldlWithKey' = C.foldlWithKey' f ([], 0) =*= Map.foldlWithKey' f ([], 0)
  where
    f (l,s) k v = (k:l,s+v)

t_elems :: CBProp
t_elems = C.elems =*= Map.elems

t_keys :: CBProp
t_keys = C.keys =*= Map.keys

t_keysSet :: CBProp
t_keysSet = CSet.toList . C.keysSet =*= Set.toList . Map.keysSet

#if MIN_VERSION_containers(0,5,0)
t_fromSet :: CBProp
t_fromSet = (C.fromSet f . C.keysSet) =*= (Map.fromSet f . Map.keysSet)
  where f = length . show
#endif

t_map :: CBProp
t_map = C.map (+3) =*= Map.map (+3)

t_mapKeys :: CBProp
t_mapKeys = C.mapKeys prepends =*= Map.mapKeys prepends

t_mapKeysWith :: CBProp
t_mapKeysWith = C.mapKeysWith (+) prepends =*= Map.mapKeysWith (+) prepends

t_mapKeysMonotonic :: CBProp
t_mapKeysMonotonic =
  C.mapKeysMonotonic prepends =*= Map.mapKeysMonotonic prepends

t_mapAccumRWithKey :: CBProp
t_mapAccumRWithKey = C.mapAccumRWithKey f 0 =*= Map.mapAccumRWithKey f 0
  where f i _ v = (i + 1 :: Int, show $ v + 3)

t_mapAccumWithKey :: CBProp
t_mapAccumWithKey = C.mapAccumWithKey f 0 =*= Map.mapAccumWithKey f 0
  where f i _ v = (i + 1 :: Int, show $ v + 3)

t_toAscList :: CBProp
t_toAscList = C.toAscList =*= Map.toAscList

t_toDescList :: CBProp
t_toDescList = C.toDescList =*= Map.toDescList

t_fromAscList :: CBProp
t_fromAscList = (C.fromAscList =*== Map.fromAscList) sort

t_fromAscListWith :: CBProp
t_fromAscListWith =
    (C.fromAscListWith (+) =*== Map.fromAscListWith (+)) sort

t_fromAscListWithKey :: CBProp
t_fromAscListWithKey =
    (C.fromAscListWithKey kvvf =*== Map.fromAscListWithKey kvvf) sort

t_fromDistinctAscList :: CBProp
t_fromDistinctAscList = (C.fromDistinctAscList =*== Map.fromDistinctAscList) p
  where p = nubBy ((==) `on` fst) . sort

t_filter :: CBProp
t_filter = C.filter p =*= Map.filter p
  where p = (> (maxBound - minBound) `div` 2)

t_split :: WithKeyProp
t_split = C.split =?*= Map.split

t_splitLookup :: WithKeyProp
t_splitLookup = C.splitLookup =?*= Map.splitLookup

t_isSubmapOf :: WithMapProp
t_isSubmapOf = C.isSubmapOf =**= Map.isSubmapOf

t_isSubmapOfBy :: WithMapProp
t_isSubmapOfBy = C.isSubmapOfBy (<=) =**= Map.isSubmapOfBy (<=)

t_isProperSubmapOf :: WithMapProp
t_isProperSubmapOf = C.isProperSubmapOf =**= Map.isProperSubmapOf

t_isProperSubmapOfBy :: WithMapProp
t_isProperSubmapOfBy = C.isProperSubmapOfBy (<=) =**= Map.isProperSubmapOfBy (<=)

t_findMin :: CBProp
t_findMin = notEmpty (C.findMin =*= Map.findMin)

t_findMax :: CBProp
t_findMax = notEmpty (C.findMax =*= Map.findMax)

t_deleteMin :: CBProp
t_deleteMin = C.deleteMin =*= Map.deleteMin

t_deleteMax :: CBProp
t_deleteMax = C.deleteMax =*= Map.deleteMax

t_deleteFindMin :: CBProp
t_deleteFindMin = notEmpty (C.deleteFindMin =*= Map.deleteFindMin)

t_deleteFindMax :: CBProp
t_deleteFindMax = notEmpty (C.deleteFindMax =*= Map.deleteFindMax)

t_minView :: CBProp
t_minView = unfoldr C.minView =*= unfoldr Map.minView

t_maxView :: CBProp
t_maxView = unfoldr C.maxView =*= unfoldr Map.maxView

t_minViewWithKey :: CBProp
t_minViewWithKey = unfoldr C.minViewWithKey =*= unfoldr Map.minViewWithKey

t_maxViewWithKey :: CBProp
t_maxViewWithKey = unfoldr C.maxViewWithKey =*= unfoldr Map.maxViewWithKey

t_updateMinWithKey :: CBProp
t_updateMinWithKey = C.updateMinWithKey kvfm =*= Map.updateMinWithKey kvfm

t_updateMaxWithKey :: CBProp
t_updateMaxWithKey = C.updateMaxWithKey kvfm =*= Map.updateMaxWithKey kvfm

t_insert :: WithKeyValueProp
t_insert = C.insert =??*= Map.insert

t_insertWith :: WithKeyValueProp
t_insertWith = C.insertWith (-) =??*= Map.insertWith (-)

t_insertWithKey :: WithKeyValueProp
t_insertWithKey = C.insertWithKey kvvf =??*= Map.insertWithKey kvvf

t_insertLookupWithKey :: WithKeyValueProp
t_insertLookupWithKey = C.insertLookupWithKey kvvf =??*=
                        Map.insertLookupWithKey kvvf

t_foldMap :: CBProp
t_foldMap = foldMap Sum =*= foldMap Sum

t_mapWithKey :: CBProp
t_mapWithKey = C.mapWithKey kvf =*= Map.mapWithKey kvf

#if MIN_VERSION_containers(0,5,0)
t_traverseWithKey :: CBProp
t_traverseWithKey = runIdentity . C.traverseWithKey f =*=
                    runIdentity . Map.traverseWithKey f
  where f _   = Identity . show . (+3)
#endif

t_alter :: WithKeyProp
t_alter = C.alter f =?*= Map.alter f
  where f = Just . maybe 1 (+1)

t_alter_delete :: WithKeyProp
t_alter_delete = C.alter (const Nothing) =?*= Map.alter (const Nothing)

t_partitionWithKey :: CBProp
t_partitionWithKey = C.partitionWithKey p =*= Map.partitionWithKey p
  where p k v = odd $ C.byteCount k + fromIntegral v

t_partition :: CBProp
t_partition = C.partition odd =*= Map.partition odd

propertiesFor :: (Arbitrary k, CritBitKey k, Ord k, IsString k, Monoid k, Show k) => k -> [Test]
propertiesFor w = [
    testProperty "t_fromList" $ t_fromList t
  , testProperty "t_fromListWith" $ t_fromListWith t
  , testProperty "t_fromListWithKey" $ t_fromListWithKey t
  , testProperty "t_null" $ t_null t
  , testProperty "t_size" $ t_size t
#if MIN_VERSION_containers(0,5,0)
  ] ++ presentMissingProperty "t_lookupGT" t_lookupGT t ++ [
  ] ++ presentMissingProperty "t_lookupGE" t_lookupGE t ++ [
  ] ++ presentMissingProperty "t_lookupLT" t_lookupLT t ++ [
  ] ++ presentMissingProperty "t_lookupLE" t_lookupLE t ++ [
#endif
  ] ++ presentMissingProperty "t_lookup" t_lookup t ++ [
  ] ++ presentMissingProperty "t_delete" t_delete t ++ [
  ] ++ presentMissingProperty "t_adjust" t_adjust t ++ [
  ] ++ presentMissingProperty "t_adjustWithKey" t_adjustWithKey t ++ [
  ] ++ presentMissingProperty "t_update" t_update t ++ [
  ] ++ presentMissingProperty "t_updateWithKey" t_updateWithKey t ++ [
  ] ++ presentMissingProperty "t_updateLookupWithKey" t_updateLookupWithKey t ++ [
    testProperty "t_mapMaybe" $ t_mapMaybe t
  , testProperty "t_mapMaybeWithKey" $ t_mapMaybeWithKey t
  , testProperty "t_mapEither" $ t_mapEither t
  , testProperty "t_mapEitherWithKey" $ t_mapEitherWithKey t
  , testProperty "t_unionL" $ t_unionL t
  , testProperty "t_unionR" $ t_unionR t
  , testProperty "t_unionWith" $ t_unionWith t
  , testProperty "t_unionWithKey" $ t_unionWithKey t
  , testProperty "t_unions" $ t_unions t
  , testProperty "t_unionsWith" $ t_unionsWith t
  , testProperty "t_difference" $ t_difference t
  , testProperty "t_differenceWith" $ t_differenceWith t
  , testProperty "t_differenceWithKey" $ t_differenceWithKey t
  , testProperty "t_intersection" $ t_intersection t
  , testProperty "t_intersectionWith" $ t_intersectionWith t
  , testProperty "t_intersectionWithKey" $ t_intersectionWithKey t
  , testProperty "t_foldl" $ t_foldl t
  , testProperty "t_foldlWithKey" $ t_foldlWithKey t
  , testProperty "t_foldl'" $ t_foldl' t
  , testProperty "t_foldlWithKey'" $ t_foldlWithKey' t
  , testProperty "t_elems" $ t_elems t
  , testProperty "t_keys" $ t_keys t
  , testProperty "t_keysSet" $ t_keysSet t
#if MIN_VERSION_containers(0,5,0)
  , testProperty "t_fromSet" $ t_fromSet t
#endif
  , testProperty "t_map" $ t_map t
  , testProperty "t_mapWithKey" $ t_mapWithKey t
  , testProperty "t_mapKeys" $ t_mapKeys t
  , testProperty "t_mapKeysWith" $ t_mapKeysWith t
  , testProperty "t_mapKeysMonotonic" $ t_mapKeysMonotonic t
  , testProperty "t_mapAccumWithKey" $ t_mapAccumWithKey t
  , testProperty "t_mapAccumRWithKey" $ t_mapAccumRWithKey t
  , testProperty "t_toAscList" $ t_toAscList t
  , testProperty "t_toDescList" $ t_toDescList t
  , testProperty "t_fromAscList" $ t_fromAscList t
  , testProperty "t_fromAscListWith" $ t_fromAscListWith t
  , testProperty "t_fromAscListWithKey" $ t_fromAscListWithKey t
  , testProperty "t_fromDistinctAscList" $ t_fromDistinctAscList t
  , testProperty "t_insertLookupWithKey" $ t_insertLookupWithKey t
  , testProperty "t_filter" $ t_filter t
  ] ++ presentMissingProperty "t_split" t_split t ++ [
  ] ++ presentMissingProperty "t_splitLookup" t_splitLookup t ++ [
    testProperty "t_isSubmapOf" $ t_isSubmapOf t
  , testProperty "t_isSubmapOfBy" $ t_isSubmapOfBy t
  , testProperty "t_isProperSubmapOf" $ t_isProperSubmapOf t
  , testProperty "t_isProperSubmapOfBy" $ t_isProperSubmapOfBy t
  , testProperty "t_findMin" $ t_findMin t
  , testProperty "t_findMax" $ t_findMax t
  , testProperty "t_deleteMin" $ t_deleteMin t
  , testProperty "t_deleteMax" $ t_deleteMax t
  , testProperty "t_deleteFindMin" $ t_deleteFindMin t
  , testProperty "t_deleteFindMax" $ t_deleteFindMax t
  , testProperty "t_minView" $ t_minView t
  , testProperty "t_maxView" $ t_maxView t
  , testProperty "t_minViewWithKey" $ t_minViewWithKey t
  , testProperty "t_maxViewWithKey" $ t_maxViewWithKey t
  , testProperty "t_updateMinWithKey" $ t_updateMinWithKey t
  , testProperty "t_updateMaxWithKey" $ t_updateMaxWithKey t
  ] ++ presentMissingProperty "t_insert" t_insert t ++ [
  ] ++ presentMissingProperty "t_insertWith" t_insertWith t ++ [
  ] ++ presentMissingProperty "t_insertWithKey" t_insertWithKey t ++ [
    testProperty "t_insertLookupWithKey" $ t_insertLookupWithKey t
#if MIN_VERSION_containers(0,5,0)
  , testProperty "t_traverseWithKey" $ t_traverseWithKey t
#endif
  , testProperty "t_foldMap" $ t_foldMap t
  , testProperty "t_alter" $ t_alter t
  , testProperty "t_alter_delete" $ t_alter_delete t
  , testProperty "t_partition" $ t_partition t
  , testProperty "t_partitionWithKey" $ t_partitionWithKey t
  ]
  where
    t = sameAs w

    sameAs :: (CritBitKey k, Ord k) => k -> SA k
    sameAs _ = SameAs C.fromList C.toList Map.fromList Map.toList

properties :: [Test]
properties = [
    testGroup "text" $ propertiesFor T.empty
  , testGroup "bytestring" $ propertiesFor B.empty
  ]

instance (Eq k, Eq v) => Eq' (CritBit k v) (Map k v) where
   c =^= m = C.toList c =^= Map.toList m

instance (Eq' a1 b1, Eq k, Eq v) => Eq' (a1, CritBit k v) (b1, Map k v) where
  (a1, a2) =^= (b1, b2) = a1 =^= b1 && a2 =^= b2

-- Handy functions for fiddling with from ghci.

blist :: [B.ByteString] -> CritBit B.ByteString Word8
blist = C.fromList . flip zip [0..]

tlist :: [T.Text] -> CritBit T.Text Word8
tlist = C.fromList . flip zip [0..]

mlist :: [B.ByteString] -> Map B.ByteString Word8
mlist = Map.fromList . flip zip [0..]