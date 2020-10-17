{-# LANGUAGE
   MultiParamTypeClasses,
   FlexibleInstances,
   ApplicativeDo,
   DeriveFunctor,
   GeneralizedNewtypeDeriving  #-}

import Control.Monad.Identity
import Data.Bifunctor (bimap)
import Control.Applicative
import Data.List.NonEmpty (unzip)
import Prelude hiding (unzip)

class Level n f where
  level :: Int -> f n

class Level n f => LevelRing n f where
  add :: f n -> f n -> f n

instance (Num n, Show n) => Level n IO where
  level x = putStr "new level: " *> print x *> pure (fromIntegral x)

instance (Num n, Show n) => LevelRing n IO where
  add = liftA2 (+)

instance Applicative f => Level String f where
  level = pure . show

instance Applicative f => LevelRing String f where
  add = liftA2 pretty where pretty x y = "(+ " ++ x ++ " " ++ y ++ ")"

newtype Wrong x = Wrong x deriving (Show, Functor)

instance Applicative Wrong where
  pure = Wrong
  liftA2 f (Wrong a) (Wrong b) = Wrong (f a b)

instance Num n => Level n Wrong where
  level = pure . fromIntegral

instance Num n => LevelRing n Wrong where
  add = liftA2 (-)

data Ring = Level Int | Add Ring Ring deriving Show

instance Applicative f => Level Ring f where
  level = pure . Level

instance Applicative f => LevelRing Ring f where
  add = liftA2 Add

r :: Identity Ring -> Identity Ring
r = id

eval :: Ring -> Int
eval (Add x y) = eval x + eval y
eval (Level x) = x

generalize :: LevelRing n f => Ring -> f n
generalize (Add x y) = generalize x `add` generalize y
generalize (Level x) = level x

w :: Wrong Int -> Wrong Int
w = id

example :: LevelRing n f => f n
example = level 10 `add` level 1

another :: LevelRing n f => f n
another = example
    `add` generalize (Level 1 `Add` (Level 4 `Add` Level 5))
    `add` level 0

instance (Applicative f, Level n f, Level m f) => Level (n, m) f where
  level x = (,) <$> level x <*> level x

instance (Applicative f, LevelRing n f, LevelRing m f) => LevelRing (n, m) f where
  add x y = (,) <$> (xn `add` yn) <*> (xm `add` ym) where
    (xn, xm) = unzip x
    (yn, ym) = unzip y

dup :: (Applicative f, LevelRing n f, LevelRing m f) => f (n, m) -> f (n, m)
dup = id

io :: IO Int -> IO Int
io = id

i :: Identity Int -> Identity Int
i = id

main :: IO ()
main = do x <- io example
          putStrLn ("result: " ++ show x)
          print (w example)
          print (r example)
          print (fst <$> thing)
          print (snd <$> thing)
  where
    thing :: Identity (Ring, String)
    thing = another
