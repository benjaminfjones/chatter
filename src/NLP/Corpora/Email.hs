{-# LANGUAGE OverloadedStrings #-}
-- | Utilities for reading mailman-style email archives.
module NLP.Corpora.Email where

import qualified Data.ByteString as BS
import Data.List (isSuffixOf)
import Data.List.Split (splitWhen)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Data.Text.Encoding as TE

import Data.MBox

import System.Directory (getDirectoryContents)
import System.FilePath ((</>))

import NLP.Tokenize (tokenize)

-- | Path to the directory containing all the PLUG archives.
plugDataPath :: FilePath
plugDataPath = "./data/corpora/PLUG/"

plugArchiveText :: IO [Text]
plugArchiveText = do
  archive <- fullPlugArchive
  return $ map body archive

plugArchiveTokens :: IO [[Text]]
plugArchiveTokens = do
  archive <- fullPlugArchive
  return $ map (tokenize . body) archive

fullPlugArchive :: IO [Message]
fullPlugArchive = do
  files <- getDirectoryContents plugDataPath
  let archiveFiles = filter (".txt" `isSuffixOf`) files
  contents <- mapM (\f->readF (plugDataPath </> f)) archiveFiles
  return $ concatMap parseMBox contents

readF :: FilePath -> IO Text
readF file = do
  bs <- BS.readFile file
  return $ TE.decodeLatin1 bs