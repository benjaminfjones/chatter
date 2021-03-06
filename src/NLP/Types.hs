{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module NLP.Types
where

import Data.ByteString (ByteString)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Serialize (Serialize, put, get, getTwoOf, putTwoOf)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8, decodeUtf8)
import GHC.Generics

type Sentence = [Text]
type TaggedSentence = [(Text, Tag)]


-- | Part of Speech tagger, with back-off tagger.
--
-- A sequence of pos taggers can be assembled by using backoff
-- taggers.  When tagging text, the first tagger is run on the input,
-- possibly tagging some tokens as unknown ('Tag "Unk"').  The first
-- backoff tagger is then recursively invoked on the text to fill in
-- the unknown tags, but that may still leave some tokens marked with
-- 'Tag "Unk"'.  This process repeats until no more taggers are found.
-- (The current implementation is not very efficient in this
-- respect.).
--
-- Back off taggers are particularly useful when there is a set of
-- domain specific vernacular that a general purpose statistical
-- tagger does not know of.  A LitteralTagger can be created to map
-- terms to fixed POS tags, and then delegate the bulk of the text to
-- a statistical back off tagger, such as an AvgPerceptronTagger.
--
-- `POSTagger` values can be serialized and deserialized by using
-- `NLP.POS.serialize` and NLP.POS.deserialize`. This is a bit tricky
-- because the POSTagger abstracts away the implementation details of
-- the particular tagging algorithm, and the model for that tagger (if
-- any).  To support serialization, each POSTagger value must provide
-- a serialize value that can be used to generate a `ByteString`
-- representation of the model, as well as a unique id (also a
-- `ByteString`).  Furthermore, that ID must be added to a `Map
-- ByteString (ByteString -> Maybe POSTagger -> Either String
-- POSTagger)` that is provided to `deserialize`.  The function in the
-- map takes the output of `posSerialize`, and possibly a backoff
-- tagger, and reconstitutes the POSTagger that was serialized
-- (assigning the proper functions, setting up closures as needed,
-- etc.) Look at the source for `NLP.POS.taggerTable` and
-- `NLP.POS.UnambiguousTagger.readTagger` for examples.
--
data POSTagger = POSTagger
    { posTagger  :: [Sentence] -> [TaggedSentence] -- ^ The initial part-of-speech tagger.
    , posTrainer :: [TaggedSentence] -> IO POSTagger -- ^ Training function to train the immediate POS tagger.
    , posBackoff :: Maybe POSTagger    -- ^ A tagger to invoke on unknown tokens.
    , posTokenizer :: Text -> Sentence -- ^ A tokenizer; (`Data.Text.words` will work.)
    , posSplitter :: Text -> [Text] -- ^ A sentence splitter.  If your input is formatted as
                                    -- one sentence per line, then use `Data.Text.lines`,
                                    -- otherwise try Erik Kow's fullstop library.
    , posSerialize :: ByteString -- ^ Store this POS tagger to a
                                 -- bytestring.  This does /not/
                                 -- serialize the backoff taggers.
    , posID :: ByteString -- ^ A unique id that will identify the
                          -- algorithm used for this POS Tagger.  This
                          -- is used in deserialization
    }

-- | Remove the tags from a tagged sentence
stripTags :: TaggedSentence -> Sentence
stripTags = map fst

newtype Tag = Tag Text
  deriving (Ord, Eq, Read, Show, Generic)

instance Serialize Tag

fromTag :: Tag -> Text
fromTag (Tag t) = t

parseTag :: Text -> Tag
parseTag t = Tag t

-- | Constant tag for "unknown"
tagUNK :: Tag
tagUNK = Tag "Unk"

instance Serialize Text where
  put txt = put $ encodeUtf8 txt
  get     = fmap decodeUtf8 get

-- | Document corpus.
--
-- This is a simple hashed corpus, the document content is not stored.
data Corpus = Corpus { corpLength     :: Int
                     -- ^ The number of documents in the corpus.
                     , corpTermCounts :: Map Text Int
                     -- ^ A count of the number of documents each term occurred in.
                     } deriving (Read, Show, Eq, Ord)

instance Serialize Corpus where
  get   = fmap (uncurry Corpus) (getTwoOf get get)
  put c = (putTwoOf put put) (corpLength c, corpTermCounts c)

-- | Get the number of documents that a term occurred in.
termCounts :: Corpus -> Text -> Int
termCounts corpus term = Map.findWithDefault 0 term $ corpTermCounts corpus

-- | Add a document to the corpus.
--
-- This can be dangerous if the documents are pre-processed
-- differently.  All corpus-related functions assume that the
-- documents have all been tokenized and the tokens normalized, in the
-- same way.
addDocument :: Corpus -> [Text] -> Corpus
addDocument (Corpus count m) doc = Corpus (count + 1) (foldl addTerm m doc)

-- | Create a corpus from a list of documents, represented by
-- normalized tokens.
mkCorpus :: [[Text]] -> Corpus
mkCorpus docs =
  let docSets = map Set.fromList docs
  in Corpus { corpLength     = length docs
            , corpTermCounts = foldl addTerms Map.empty docSets
            }

addTerms :: Map Text Int -> Set Text -> Map Text Int
addTerms m terms = Set.foldl addTerm m terms

addTerm :: Map Text Int -> Text -> Map Text Int
addTerm m term = Map.alter increment term m
  where
    increment :: Maybe Int -> Maybe Int
    increment Nothing  = Just 1
    increment (Just i) = Just (i + 1)
