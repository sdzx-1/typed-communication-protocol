{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# HLINT ignore "Use lambda-case" #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# OPTIONS_GHC -Wno-unused-do-bind #-}

module Book1 where

import Control.Concurrent (forkIO)
import Control.Concurrent.STM
import Control.Monad
import Data.IFunctor (At (..), returnAt)
import qualified Data.IFunctor as I
import Data.Kind
import Data.SR
import TypedProtocol.Codec
import TypedProtocol.Core
import TypedProtocol.Driver

{-

-----------------------------------------------------------------------------------------------
    Buyer                                                      Seller                  Buyer2
    :S0                                                        :S0
     <                     Title String  ->                     >
    :S1                                                        :S1
     <                     <-  Price Int                         >
    :S11                                                       :S12                    :S11
     <                                  PriceToBuyer2 Int ->                            >
    :S110                                                                              :S110
     <                                  <- HalfPrice  Int                               >
    :S12                                                                               :End

   ---------------------------------------------------------------------
   |:S12                                                       :S12
   | <                  Afford ->                               >
   |:S3                                                        :S3
   | <                  <- Data Int                             >
   |:End                                                       :End
   ---------------------------------------------------------------------

   ---------------------------------------------------------------------
   |:S12                                                       :S12
   | <                  NotBuy ->                               >
   |:End                                                       :End
   ---------------------------------------------------------------------
-}

data Role = Buyer | Seller | Buyer2
  deriving (Show, Eq, Ord)

data SRole :: Role -> Type where
  SBuyer :: SRole Buyer
  SBuyer2 :: SRole Buyer2
  SSeller :: SRole Seller

type instance Sing = SRole

instance SingI Buyer where
  sing = SBuyer

instance SingI Buyer2 where
  sing = SBuyer2

instance SingI Seller where
  sing = SSeller

instance Reify Buyer where
  reifyProxy _ = Buyer

instance Reify Buyer2 where
  reifyProxy _ = Buyer2

instance Reify Seller where
  reifyProxy _ = Seller

data BookSt
  = S0
  | S1
  | S11
  | S110
  | S12
  | S3
  | End

data SBookSt :: BookSt -> Type where
  SS0 :: SBookSt S0
  SS1 :: SBookSt S1
  SS11 :: SBookSt S11
  SS110 :: SBookSt S110
  SS12 :: SBookSt S12
  SS3 :: SBookSt S3
  SEnd :: SBookSt End

type instance Sing = SBookSt

instance SingI S0 where
  sing = SS0

instance SingI S1 where
  sing = SS1

instance SingI S11 where
  sing = SS11

instance SingI S110 where
  sing = SS110

instance SingI S12 where
  sing = SS12

instance SingI S3 where
  sing = SS3

instance SingI End where
  sing = SEnd

type Date = Int

instance Protocol Role BookSt where
  type Done Buyer = End
  type Done Seller = End
  type Done Buyer2 = End
  data Msg Role BookSt send recv from to where
    Title :: String -> Msg Role BookSt Buyer Seller S0 '(S1, S1)
    Price :: Int -> Msg Role BookSt Seller Buyer S1 '(S12, S11)
    PriceToB2 :: Int -> Msg Role BookSt Buyer Buyer2 S11 '(S110, S110)
    HalfPrice :: Int -> Msg Role BookSt Buyer2 Buyer S110 '(End, S12)
    Afford :: Msg Role BookSt Buyer Seller S12 '(S3, S3)
    Date :: Date -> Msg Role BookSt Seller Buyer S3 '(End, End)
    NotBuy :: Msg Role BookSt Buyer Seller S12 '(End, End)

codecRoleBookSt
  :: forall m
   . (Monad m)
  => Codec Role BookSt CodecFailure m (AnyMessage Role BookSt)
codecRoleBookSt = Codec{encode, decode}
 where
  encode _ = AnyMessage
  decode
    :: forall (r :: Role) (from :: BookSt)
     . Agency Role BookSt r from
    -> m
        ( DecodeStep
            (AnyMessage Role BookSt)
            CodecFailure
            m
            (SomeMsg Role BookSt r from)
        )
  decode stok =
    pure $ DecodePartial $ \mb ->
      case mb of
        Nothing -> return $ DecodeFail (CodecFailure "expected more data")
        Just (AnyMessage msg) -> return $
          case (stok, msg) of
            (Agency SBuyer SS1, Price{}) -> DecodeDone (SomeMsg (Recv msg)) Nothing
            (Agency SBuyer SS110, HalfPrice{}) -> DecodeDone (SomeMsg (Recv msg)) Nothing
            (Agency SBuyer SS3, Date{}) -> DecodeDone (SomeMsg (Recv msg)) Nothing
            (Agency SSeller SS0, Title{}) -> DecodeDone (SomeMsg (Recv msg)) Nothing
            (Agency SSeller SS12, Afford{}) -> DecodeDone (SomeMsg (Recv msg)) Nothing
            (Agency SSeller SS12, NotBuy{}) -> DecodeDone (SomeMsg (Recv msg)) Nothing
            (Agency SBuyer2 SS11, PriceToB2{}) -> DecodeDone (SomeMsg (Recv msg)) Nothing
            _ -> error "np"

budget :: Int
budget = 16

buyerPeer
  :: Peer Role BookSt Buyer IO (At (Maybe Date) (Done Buyer)) S0
buyerPeer = I.do
  liftm $ putStrLn "buyer send: haskell book"
  yield (Title "haskell book")
  Recv (Price i) <- await
  liftm $ putStrLn "buyer recv: price"
  liftm $ putStrLn "buyer send price to b2"
  yield (PriceToB2 i)
  Recv (HalfPrice hv) <- await
  liftm $ putStrLn "buyer recv: b2 half price"
  if i <= hv + budget
    then I.do
      liftm $ putStrLn "buyer can buy, send Afford"
      yield Afford
      Recv (Date d) <- await
      liftm $ putStrLn "buyer recv: Date, Finish"
      returnAt (Just d)
    else I.do
      liftm $ putStrLn "buyer can't buy, send NotBuy, Finish"
      yield NotBuy
      returnAt Nothing

buyerPeer2
  :: Peer Role BookSt Buyer2 IO (At () (Done Buyer2)) S11
buyerPeer2 = I.do
  Recv (PriceToB2 i) <- await
  liftm $ putStrLn "buyer2 recv: price"
  liftm $ putStrLn "buyer2 send half price to buyer, Finish"
  yield (HalfPrice (i `div` 2))

sellerPeer :: Peer Role BookSt Seller IO (At () (Done Seller)) S0
sellerPeer = I.do
  Recv (Title _name) <- await
  liftm $ putStrLn "seller recv: Title"
  liftm $ putStrLn "seller send: Price"
  yield (Price 30)
  Recv msg <- await
  case msg of
    Afford -> I.do
      liftm $ putStrLn "seller recv: Afford"
      liftm $ putStrLn "seller send: Date, Finish"
      yield (Date 100)
    NotBuy -> I.do
      liftm $ putStrLn "seller recv: NotBuy, Finish"
      returnAt ()

newTMV :: s -> IO (s, TMVar a)
newTMV s = do
  ntmv <- newEmptyTMVarIO
  pure (s, ntmv)

runAll :: IO ()
runAll = do
  buyerTMVar <- newEmptyTMVarIO @(AnyMessage Role BookSt)
  buyer2TMVar <- newEmptyTMVarIO @(AnyMessage Role BookSt)
  sellerTMVar <- newEmptyTMVarIO @(AnyMessage Role BookSt)

  let sendFun :: forall r. Sing (r :: Role) -> AnyMessage Role BookSt -> IO ()
      sendFun sr a = case sr of
        SBuyer -> atomically $ putTMVar buyerTMVar a
        SBuyer2 -> atomically $ putTMVar buyer2TMVar a
        SSeller -> atomically $ putTMVar sellerTMVar a

  let chanSeller = mvarsAsChannel sellerTMVar sendFun
      chanBuyer2 = mvarsAsChannel buyer2TMVar sendFun
      chanBuyer = mvarsAsChannel buyerTMVar sendFun

  forkIO $ void $ do
    runPeerWithDriver (driverSimple codecRoleBookSt chanSeller) sellerPeer Nothing

  forkIO $ void $ do
    runPeerWithDriver (driverSimple codecRoleBookSt chanBuyer2) buyerPeer2 Nothing

  runPeerWithDriver (driverSimple codecRoleBookSt chanBuyer) buyerPeer Nothing
  pure ()
