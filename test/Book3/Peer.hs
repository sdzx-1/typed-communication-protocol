{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module Book3.Peer where

import Book3.Type
import Control.Monad.IO.Class (liftIO)
import Data.IFunctor (At (..), ireturn, returnAt)
import qualified Data.IFunctor as I
import Data.Kind
import System.Random (randomIO)
import TypedProtocol.Core

budget :: Int
budget = 16

data CheckPriceResult :: BookSt -> Type where
  Yes :: CheckPriceResult (S3 [Enough, Support, Two, Found])
  No :: CheckPriceResult (S3 [NotEnough, Support, Two, Found])

checkPrice :: Int -> Int -> Peer Role BookSt Buyer IO CheckPriceResult (S3 s)
checkPrice _i _h = I.do
  At b <- liftm $ liftIO $ randomIO @Bool
  if b
    then LiftM $ pure (ireturn Yes)
    else LiftM $ pure (ireturn No)

data OT :: BookSt -> Type where
  OTOne :: OT (S1 [One, Found])
  OTTwo :: OT (S1 [Two, Found])

choiceOT :: Int -> Peer Role BookSt Buyer IO OT (S1 s)
choiceOT _i = I.do
  At b <- liftm $ liftIO $ randomIO @Bool
  if b
    then LiftM $ pure $ ireturn OTOne
    else LiftM $ pure $ ireturn OTTwo

buyerPeer
  :: Peer Role BookSt Buyer IO (At (Maybe Date) (Done Buyer)) S0
buyerPeer = I.do
  yield (Title "haskell book")
  await I.>>= \case
    -- The situation here is similar to below, but no warning is generated.
    Recv NoBook -> I.do
      yield SellerNoBook
      returnAt Nothing
    Recv (Price i) -> I.do
      choiceOT i I.>>= \case
        OTOne -> I.do
          yield OneAfford
          yield OneAccept
          Recv (OneDate d) <- await
          yield (OneSuccess d)
          returnAt $ Just d
        OTTwo -> I.do
          yield (PriceToBuyer2 i)
          await I.>>= \case   
          -- await ::  Peer Role BookSt 'Buyer IO (Recv Role BookSt 'Buyer ('S6 Any)) ('S6 Any)

          -- The type of message received by await is:  Recv Role BookSt 'Buyer ('S6 Any) Any
          -- Pattern match it, (Recv NotSupport1), (Recv (SupportVal h)) is suitable.
          -- But here ghc generates wrong warnings and seems to fail to perform pattern matching checks correctly.
            Recv NotSupport1 -> I.do
            -- (Recv NotSupport1)    :: Recv Role BookSt 'Buyer  (S6 '[NotSupport, Two, Found]) (S3 '[NotSupport, Two, Found])
              yield TwoNotBuy
              returnAt Nothing
            Recv (SupportVal h) -> I.do
            --  (Recv (SupportVal h)) :: Recv Role BookSt 'Buyer (S6 '[Support, Two, Found]) '(S3 s)
              checkPrice i h I.>>= \case
                Yes -> I.do
                  yield TwoAccept
                  Recv (TwoDate d) <- await
                  yield (TwoSuccess d)
                  returnAt (Just d)
                No -> I.do
                  yield TwoNotBuy1
                  yield TwoFailed
                  returnAt Nothing

data BuySupp :: BookSt -> Type where
  BNS :: BuySupp (S6 '[NotSupport, Two, Found])
  BS :: BuySupp (S6 '[Support, Two, Found])

choiceB :: Int -> Peer Role BookSt Buyer2 IO BuySupp (S6 s)
choiceB _i = I.do
  At b <- liftm $ liftIO $ randomIO @Bool
  if b
    then LiftM $ pure $ ireturn BNS
    else LiftM $ pure $ ireturn BS

buyer2Peer
  :: Peer Role BookSt Buyer2 IO (At (Maybe Date) (Done Buyer2)) (S1 s)
buyer2Peer = I.do
  await I.>>= \case
    Recv SellerNoBook -> returnAt Nothing
    Recv OneAfford -> I.do
      Recv (OneSuccess d) <- await
      returnAt (Just d)
    Recv (PriceToBuyer2 i) -> I.do
      choiceB i I.>>= \case
        BNS -> I.do
          yield NotSupport1
          returnAt Nothing
        BS -> I.do
          yield (SupportVal (i `div` 2))
          await I.>>= \case
            Recv (TwoSuccess d) -> returnAt $ Just d
            Recv TwoFailed -> returnAt Nothing

data FindBookResult :: BookSt -> Type where
  NotFound' :: FindBookResult (S2 '[NotFound])
  Found' :: FindBookResult (S2 '[Found])

findBook :: String -> Peer Role BookSt Seller IO FindBookResult (S2 s)
findBook _st = I.do
  At b <- liftm $ liftIO $ randomIO @Bool
  if b
    then LiftM $ pure (ireturn Found')
    else LiftM $ pure (ireturn NotFound')

sellerPeer :: Peer Role BookSt Seller IO (At () (Done Seller)) S0
sellerPeer = I.do
  Recv (Title st) <- await
  findBook st I.>>= \case
    NotFound' -> yield NoBook
    Found' -> I.do
      yield (Price 30)
      await I.>>= \case
        Recv OneAccept -> yield (OneDate 100)
        Recv TwoNotBuy -> returnAt ()
        Recv TwoAccept -> yield (TwoDate 100)
        Recv TwoNotBuy1 -> returnAt ()