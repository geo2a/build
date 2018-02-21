{-# LANGUAGE ExistentialQuantification, GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
module Development.Build.Store (
    -- * Basic types
    Key, Value, Hash, hash,

    -- * Store manipulation
    Store, getValue, setValue, getHash
    ) where

import Data.Map
import Data.String
import System.FilePath

import Development.Build.Utilities

-- | A 'Key' is a name of a file or, more generally, a variable. We use 'FilePath'
-- for prototyping.
type Key = FilePath

-- | A 'Value' is the contents of a file or, more generally, a variable. We use
-- @newtype Value = Value String@ for prototyping.
newtype Value = Value String deriving (Eq, IsString, Show)

-- | A 'Hash' is used for efficient tracking and sharing of build results. We
-- use @newtype Hash = Hash Value@ for prototyping.
newtype Hash = Hash Value deriving (Eq, Show)

-- | Compute the 'Hash' of a given 'Value'. We typically assume cryptographic
-- hashing, e.g. SHA256. Here we use @hash v = Hash v@ for prototyping.
hash :: Value -> Hash
hash = Hash

-- | A key-value store, which in addition to usual 'getValue' and 'setValue'
-- queries supports 'getHash store key', which is required to be equivalent to
-- 'hash (getValue store key)' but can in some cases be implemented more
-- efficiently. For example, GVFS (Git Virtual File System) downloads actual
-- values (file contents) only on demand. Note that if a file does not exist,
-- the corresponding 'file not found' value (suitably encoded) is still useful
-- and can be tracked by a build system. See 'consistent' for the list of
-- invariants that must be satisfied by a 'Store'.
data Store = forall s. Store s (s -> Key -> Value) (Key -> Value -> s -> s) (s -> Key -> Hash)

-- | Lookup the 'Value' of a 'Key' in a 'Store'.
getValue :: Store -> Key -> Value
getValue (Store s f _ _) = f s

-- | Modify a 'Store'.
setValue :: Store -> Key -> Value -> Store
setValue (Store s f g h) key value = Store (g key value s) f g h

-- | Lookup the 'Hash' of a 'Key' in a 'Store'.
getHash :: Store -> Key -> Hash
getHash (Store s _ _ h) = h s

-- | Example 'Store' implemented using a @Map Key Value@. For simplicity, the
-- the current implementation throws an error when accessing non-existent 'Key'.
mapStore :: Store
mapStore = Store empty (!) insert ((hash .) . (!))

instance Eq Store where
    s1 == s2 = forall $ \key -> getValue s1 key == getValue s2 key

-- | A store is consistent if it satisfies 4 invariants:
-- * Get after set: @getValue (setValue s k v) k == v@.
-- * Set after get: @setValue s k (getValue s k) == s@.
-- * Set after set: @setValue (setValue s k v1) k v2 == setValue s k v2@.
-- * Hash is consitent: @hash (getValue s k) == getHash s k@.
consistent :: Store -> Bool
consistent store = forall $ \(store, key, value, value') ->
    -- Get after set
    getValue (setValue store key value) key == value
    &&
    -- Set after get
    setValue store key (getValue store key) == store
    &&
    -- Set after set
    setValue (setValue store key value') key value == setValue store key value
    &&
    -- Hash is consitent
    hash (getValue store key) == getHash store key