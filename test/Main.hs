module Main (main) where

import qualified Book as Book
import qualified Book1 as Book1
-- import qualified Book2 as Book2
import Control.Concurrent (threadDelay)
main :: IO ()
main = do  
  putStrLn "----------------- run Book -----------------"
  Book.runAll
  putStrLn "---------------- run Book1 -----------------"
  Book1.runAll
  -- putStrLn "---------------- run Book2 -----------------"
  -- Book2.runAll
  threadDelay 100
  putStrLn "--------------------------------------------"
