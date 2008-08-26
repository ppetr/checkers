{-# LANGUAGE ScopedTypeVariables, FlexibleContexts, KindSignatures
           , Rank2Types, TypeOperators
  #-}

{-# OPTIONS_GHC -Wall #-}
----------------------------------------------------------------------
-- |
-- Module      :  Test.QuickCheck.Classes
-- Copyright   :  (c) Conal Elliott 2008
-- License     :  BSD3
-- 
-- Maintainer  :  conal@conal.net
-- Stability   :  experimental
-- 
-- Some QuickCheck properties for standard type classes
----------------------------------------------------------------------

module Test.QuickCheck.Classes
  (
    monoid, monoidMorphism, semanticMonoid
  , functor, functorMorphism, semanticFunctor, functorMonoid
  , applicative, applicativeMorphism, semanticApplicative
  , monad, monadMorphism, semanticMonad
  , arrow, arrowChoice
  )
  where

import Data.Monoid
import Control.Applicative
import Control.Monad (join)
import Control.Arrow (Arrow,ArrowChoice,first,second,left,right,(>>>),arr)
import Test.QuickCheck
import Text.Show.Functions ()

import Test.QuickCheck.Help
import Test.QuickCheck.Instances.Char ()


-- | Properties to check that the 'Monoid' 'a' satisfies the monoid
-- properties.  The argument value is ignored and is present only for its
-- type.
monoid :: forall a. (Monoid a, Show a, Arbitrary a, EqProp a) =>
          a -> TestBatch
monoid = const ( "monoid"
               , [ ("left  identity", leftId  mappend (mempty :: a))
                 , ("right identity", rightId mappend (mempty :: a))
                 , ("associativity" , isAssoc (mappend :: Binop a))
                 ]
               )

-- | Monoid homomorphism properties.  See also 'homomorphism'.
monoidMorphism :: (Monoid a, Monoid b, EqProp b, Show a, Arbitrary a) =>
                  (a -> b) -> TestBatch
monoidMorphism q = ("monoid morphism", homomorphism monoidD monoidD q)

semanticMonoid :: forall a b.
  ( Model a b
  , Monoid a
  , Monoid b
  , Show a
  , Arbitrary a
  , EqProp b
  ) =>
  a -> TestBatch
semanticMonoid = const (first ("semantic " ++)
                              (monoidMorphism (model:: a -> b)))

functorMonoid :: forall m a b.
  ( Functor m
  , Monoid (m a)
  , Monoid (m b)
  , Arbitrary (a->b)
  , Arbitrary (m a)
  , Show (m a)
  , EqProp (m b)) =>
  m (a,b) -> TestBatch
functorMonoid = const ("functor-monoid"
                      , [ ( "identity",property identityP )
                        , ( "binop", property binopP )
                        ]
                      )
  where
    identityP :: (a->b) -> Property
    identityP f = (fmap f) (mempty :: m a) =-= (mempty :: m b)
    binopP :: (a->b) -> (m a) -> (m a) -> Property
    binopP f u v = (fmap f) (u `mappend` v) =-= (fmap f u) `mappend` (fmap f v)

-- <camio> There I have an attempt at doing this. I eventually implemented 
-- those semanticMorphisms as their own functions. I'm not too thrilled with
-- that implementation, but it works.

-- TODO: figure out out to eliminate the redundancy.

-- | Properties to check that the 'Functor' @m@ satisfies the functor
-- properties.
functor :: forall m a b c.
           ( Functor m
           , Arbitrary a, Arbitrary b, Arbitrary c
           , Show (m a), Arbitrary (m a), EqProp (m a), EqProp (m c)) =>
           m (a,b,c) -> TestBatch
functor = const ( "functor"
                , [ ("identity", property identityP)
                  , ("compose" , property composeP) ]
                )
 where
   identityP :: Property
   composeP  :: (b -> c) -> (a -> b) -> Property
   
   identityP = fmap id =-= (id :: m a -> m a)
   composeP g f = fmap g . fmap f =-= (fmap (g.f) :: m a -> m c)

-- Note the similarity between 'functor' and 'monoidMorphism'.  The
-- functor laws say that 'fmap' is a homomorphism w.r.t '(.)':
-- 
--   functor = const ("functor", homomorphism endoMonoidD endoMonoidD fmap)
-- 
-- However, I don't think the types can work out, since 'fmap' is used at
-- three different types.


-- | 'Functor' morphism (natural transformation) properties
functorMorphism :: forall f g.
                   ( Functor f, Functor g
                   , Arbitrary (f NumericType), Show (f NumericType)
                   , EqProp (g NoPropertyType)
                   ) =>
                  (forall a. f a -> g a) -> TestBatch
functorMorphism q = ("functor morphism", [("fmap", property fmapP)])
 where
   -- fmapP :: (NumericType -> NoPropertyType) -> f NumericType -> Property
   -- fmapP h l = q (fmap h l) =-= fmap h (q l)
   fmapP :: (NumericType -> NoPropertyType) -> Property
   fmapP h = q . fmap h =-= fmap h . q

-- Note: monomorphism prevent us from saying @commutes (.) q (fmap h)@,
-- since @fmap h@ is used at two different types.

semanticFunctor :: forall f g.
  ( Model1 f g
  , Functor f
  , Functor g
  , Arbitrary (f NumericType)
  , Show (f NumericType)
  , EqProp (g NoPropertyType)
  ) =>
  f () -> TestBatch
semanticFunctor = const (functorMorphism (model1 :: forall b. f b -> g b))


-- | Properties to check that the 'Applicative' @m@ satisfies the monad
-- properties
applicative :: forall m a b c.
               ( Applicative m
               , Arbitrary a, Arbitrary b, Arbitrary (m a)
               , Arbitrary (m (b -> c)), Show (m (b -> c))
               , Arbitrary (m (a -> b)), Show (m (a -> b))
               , Show a, Show (m a)
               , EqProp (m a), EqProp (m b), EqProp (m c)
               ) =>
               m (a,b,c) -> TestBatch
applicative = const ( "applicative"
                    , [ ("identity"    , property identityP)
                      , ("composition" , property compositionP)
                      , ("homomorphism", property homomorphismP)
                      , ("interchange" , property interchangeP)
                      , ("functor"     , property functorP)
                      ]
                    )
 where
   identityP     :: m a -> Property
   compositionP  :: m (b -> c) -> m (a -> b) -> m a -> Property
   homomorphismP :: (a -> b) -> a -> Property
   interchangeP  :: m (a -> b) -> a -> Property
   functorP      :: (a -> b) -> m a -> Property
   
   identityP v        = (pure id <*> v) =-= v
   compositionP u v w = (pure (.) <*> u <*> v <*> w) =-= (u <*> (v <*> w))
   homomorphismP f x  = (pure f <*> pure x) =-= (pure (f x) :: m b)
   interchangeP u y   = (u <*> pure y) =-= (pure ($ y) <*> u)
   functorP f x       = (fmap f x) =-= (pure f <*> x)


-- | 'Applicative' morphism properties
applicativeMorphism :: forall f g.
                       ( Applicative f, Applicative g
                       , Show (f NumericType), Arbitrary (f NumericType)
                       , EqProp (g NumericType), EqProp (g NoPropertyType)
                       , Show (f (NumericType -> NoPropertyType))
                       , Arbitrary (f (NumericType -> NoPropertyType))
                       ) =>
                       (forall a. f a -> g a) -> TestBatch
applicativeMorphism q =
  ( "applicative morphism"
  , [("pure", property pureP), ("apply", property applyP)] )
 where
   pureP  :: NumericType -> Property
   applyP :: f (NumericType->NoPropertyType) -> f NumericType -> Property
   
   pureP a = q (pure a) =-= pure a
   applyP mf mx = q (mf <*> mx) =-= (q mf <*> q mx)


semanticApplicative :: forall f g.
  ( Model1 f g
  , Applicative f, Applicative g
  , Arbitrary (f NumericType), Arbitrary (f (NumericType -> NoPropertyType))
  , EqProp (g NumericType), EqProp (g NoPropertyType)
  , Show (f NumericType), Show (f (NumericType -> NoPropertyType))
  ) =>
  f () -> TestBatch
semanticApplicative =
  const (applicativeMorphism (model1 :: forall b. f b -> g b))


-- | Properties to check that the 'Monad' @m@ satisfies the monad properties
monad :: forall m a b c.
         ( Monad m
         , Show a, Arbitrary a, Arbitrary b
         , Arbitrary (m a), EqProp (m a), Show (m a)
         , Arbitrary (m b), EqProp (m b)
         , Arbitrary (m c), EqProp (m c)
         ) =>
         m (a,b,c) -> TestBatch
monad = const ( "monad laws"
              , [ ("left  identity", property leftP)
                , ("right identity", property rightP)
                , ("associativity" , property assocP)
                ]
              )
 where
   leftP  :: (a -> m b) -> a -> Property
   rightP :: m a -> Property
   assocP :: m a -> (a -> m b) -> (b -> m c) -> Property
   
   leftP f a    = (return a >>= f)  =-= f a
   rightP m     = (m >>= return)    =-=  m
   assocP m f g = ((m >>= f) >>= g) =-= (m >>= (\x -> f x >>= g))

-- | 'Monad' morphism properties

-- | 'Applicative' morphism properties
monadMorphism :: forall f g.
                 ( Monad f, Monad g, Functor g
                 , Show (f NumericType)
                 , Show (f (NumericType -> NoPropertyType))
                 , Show (f (f (NumericType -> NoPropertyType)))
                 , Arbitrary (f NumericType), Arbitrary (f NoPropertyType)
                 , Arbitrary (f (NumericType -> NoPropertyType))
                 , Arbitrary (f (f (NumericType -> NoPropertyType)))
                 , EqProp (g NumericType), EqProp (g NoPropertyType)
                 , EqProp (g (NumericType -> NoPropertyType))
                 ) =>
                (forall a. f a -> g a) -> TestBatch
monadMorphism q =
  ( "monad morphism"
  , [ ("return", property returnP), ("bind", property bindP), ("join", property joinP) ] )
 where
   returnP :: NumericType -> Property
   bindP :: f NumericType -> (NumericType -> f NoPropertyType) -> Property
   joinP :: f (f (NumericType->NoPropertyType)) -> Property
   
   returnP a = q (return a) =-= return a
   bindP u k = q (u >>= k)  =-= (q u >>= q . k)
   joinP uu  = q (join uu)  =-= join (fmap q (q uu))

-- The join and bind properties are redundant.  Pick one.

--      q (join uu)
--   == q (uu >>= id)
--   == q uu >>= q . id
--   == q uu >>= q
--   == join (fmap q (q uu))

--      q (u >>= k)
--   == q (fmap k (join u))
--   == fmap k (q (join u))  -- if also a functor morphism
--   == fmap k (join (fmap q (q uu)))
--   == fmap k (q u >>= q)
--   == ???

-- I'm stuck at the end here.  What's missing?

semanticMonad :: forall f g.
  ( Model1 f g
  , Monad f, Monad g
  , EqProp (g NoPropertyType) , EqProp (g NumericType)
  , EqProp (g (NumericType -> NoPropertyType))
  , Arbitrary (f NoPropertyType) , Arbitrary (f NumericType)
  , Arbitrary (f (f (NumericType -> NoPropertyType)))
  , Arbitrary (f (NumericType -> NoPropertyType))
  , Show (f (f (NumericType -> NoPropertyType)))
  , Show (f (NumericType -> NoPropertyType)) , Show (f NumericType)
  , Functor g
  ) =>
  f () -> TestBatch
semanticMonad = const (monadMorphism (model1 :: forall b. f b -> g b))

arrow :: forall (~>) b c d e.
         ( Arrow (~>)
         , Show (d ~> e), Show (c ~> d), Show (b ~> c)
         , Show b, Show c, Show d, Show e
         , Arbitrary (d ~> e), Arbitrary (c ~> d), Arbitrary (b ~> c)
         , Arbitrary b, Arbitrary c, Arbitrary d, Arbitrary e
         , EqProp (b ~> e), EqProp (b ~> d)
         , EqProp ((b,d) ~> c)
         , EqProp ((b,d) ~> (c,d)), EqProp ((b,e) ~> (d,e))
         , EqProp ((b,d) ~> (c,e))
         , EqProp b, EqProp c, EqProp d, EqProp e
         ) =>
         b ~> (c,d,e) -> TestBatch
arrow = const ("arrow laws"
              , [ ("associativity"           , property assocP)
                , ("arr distributes"         , property arrDistributesP)
-- TODO: how to define h is onto or one-to-one?
--                , ("extensionality principle"     , property extensionalityP)
--                , ("extensionality dual"          , property extensionalityDualP)
                 , ("first works as funs"    , property firstAsFunP)
                 , ("first keeps composition", property firstKeepCompP)
                 , ("first works as fst"     , property firstIsFstP)
                 , ("second can move"        , property secondMovesP)
                 ]
              )
  where
    assocP :: b ~> c -> c ~> d -> d ~> e -> Property
    assocP f g h = ((f >>> g) >>> h) =-= (f >>> (g >>> h))
    
    arrDistributesP :: (b -> c) -> (c -> d) -> Property
    arrDistributesP f g = ((arr (f >>> g)) :: b ~> d) =-= (arr f >>> arr g)
    
    firstAsFunP :: (b -> c) -> Property
    firstAsFunP f = (first (arr f) :: (b,d) ~> (c,d)) =-= arr (first f)

    firstKeepCompP :: b ~> c -> c ~> d -> Property
    firstKeepCompP f g =
      ((first (f >>> g)) :: ((b,e) ~> (d,e))) =-= (first f >>> first g)
 
    firstIsFstP :: b ~> c -> Property
    firstIsFstP f = ((first f :: (b,d) ~> (c,d)) >>> arr fst)
                      =-= (arr fst >>> f)
    
    secondMovesP :: (b ~> c) -> (d -> e) -> Property
    secondMovesP f g = (first f >>> second (arr g))
                         =-= ((second (arr g)) >>> first f)

arrowChoice :: forall (~>) b c d e.
               ( ArrowChoice (~>)
               , Show (b ~> c)
               , Arbitrary (b ~> c)
               , Arbitrary b, Arbitrary c, Arbitrary d, Arbitrary e
               , EqProp ((Either b d) ~> (Either c e))
               , EqProp ((Either b d) ~> (Either c d))
               ) =>
               b ~> (c,d,e) -> TestBatch
arrowChoice = const ("arrow choice laws"
                    , [ ("left works as funs"     , property leftAsFunP)
                      , ("right can move"         , property rightMovesP)
                      ]
                    )
  where
    leftAsFunP :: (b -> c) -> Property
    leftAsFunP f = (left (arr f) :: (Either b d) ~> (Either c d))
                     =-= arr (left f)

    rightMovesP :: (b ~> c) -> (d -> e) -> Property
    rightMovesP f g = (left f >>> right (arr g))
                        =-= ((right (arr g)) >>> left f)

