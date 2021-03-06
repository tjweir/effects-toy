{-# LANGUAGE PartialTypeSignatures #-}
{-# OPTIONS_GHC -Wno-partial-type-signatures #-}
module Eff.EffectsToy
  ( start
  ) where

import qualified Network.Wai as Wai
import qualified Network.HTTP.Types as HTTP
import qualified Network.Wai.Handler.Warp as Warp
import qualified Data.ByteString.Lazy as LBS
import           Data.Function
import           Data.String (fromString)
import qualified Eff.EffectsToy.Handler.ByteStream.Strict as BSStrict
import           Eff.EffectsToy.Handler.WaiHandler
import           Eff.EffectsToy.Handler.Trace.StdOut
import           Eff.EffectsToy.Handler.SQLiteSimple
import           Eff.EffectsToy.Handler.Db.TestDb.SQLite

start :: IO ()
start = do
    runBaseStack initApp
    Warp.run 8087 (runWaiApplication runBaseStack helloWorld)
  where
    initApp = initDb

runBaseStack :: _ a -> IO a
runBaseStack = runTrace
             . withConnection "/tmp/tempdb.db"
             . runTestDb

runWaiApplication :: ( Monad n
                     ) => (forall x. n x -> IO x)
                       -> _ ()
                       -> Wai.Application
runWaiApplication runToIO waiApp request respond =
    waiApp
    & runWaiHandler request
    & BSStrict.runByteStream
    & runToIO
    & (fmap toResponse)
    & (>>= respond)
  where
    toResponse (body, (headers, status)) = Wai.responseLBS status headers body

helloWorld :: ( Trace m
              , WaiHandler m
              , TestDb m
              ) => m ()
helloWorld = do
  trace "Request received"
  req <- askRequest
  tellHeaders [(HTTP.hContentType, "text/plain")]
  tellChunk "Hello, world!\n"
  (reqId, str) <- req & Wai.rawQueryString
                      & LBS.fromStrict
                      & storeAndLookup
  tellChunk $ "You requested " <> str <> "\n"
  tellChunk $ "Your request was number " <> (fromString $ show reqId)
  putStatus HTTP.ok200
