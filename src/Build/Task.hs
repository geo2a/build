{-# LANGUAGE ConstraintKinds, RankNTypes, StandaloneDeriving #-}
{-# OPTIONS_GHC -Wno-unused-top-binds #-}
module Build.Task (Task, Tasks) where

import Control.Applicative
import Control.Monad.Trans.Reader

-- Ideally we would like to write:
--
--    type Tasks c k v = k -> Maybe (Task c k v)
--    type Task  c k v = forall f. c f => (k -> f v) -> f v
--
-- Alas, we can't since it requires impredicative polymorphism and GHC currently
-- does not support it.
--
-- A usual workaround is to wrap 'Task' into a newtype, but this leads to the
-- loss of higher-rank polymorphism: for example, we can no longer apply a
-- monadic build system to an applicative task description or apply a monadic
-- 'trackM' to trace the execution of a 'Task Applicative'. This leads to severe
-- code duplication.
--
-- Our workaround is inspired by the @lens@ library, which allows us to keep
-- higher-rank polymorphism at the cost of inserting 'unwrap' in a few places
-- in our code and using slightly strange definitions of 'Tasks' and 'Task'.
-- See "Build.Task.Wrapped".
type Tasks c k v = forall f. c f => k -> Maybe ((k -> f v) -> f v)
type Task  c k v = forall f. c f =>             (k -> f v) -> f v

compose :: Tasks Monad k v -> Tasks Monad k v -> Tasks Monad k v
compose t1 t2 key = t1 key <|> t2 key

-- Old type for task descriptions, isomorphic to Tasks as demonstrated below.
type Tasks2 c k v = forall f. c f => (k -> f v) -> k -> Maybe (f v)

fromTasks :: Tasks Monad k v -> Tasks2 Monad k v
fromTasks tasks fetch key = ($fetch) <$> tasks key

toTasks :: Tasks2 Monad k v -> Tasks Monad k v
toTasks tasks2 key = runReaderT <$> tasks2 (\k -> ReaderT ($k)) key
