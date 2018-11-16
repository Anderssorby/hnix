{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}
module Nix.Effects where

import           Prelude hiding (putStr, putStrLn, print)
import qualified Prelude

import           Control.Monad.Trans
import           Data.Text (Text)
import           Nix.Frames
import           Nix.Render
import           Nix.Value
import           System.Exit
import           System.Process
import           System.Directory

-- | A path into the nix store
newtype StorePath = StorePath { unStorePath :: FilePath }

class (MonadFile m, MonadStore m, MonadPutStr m) => MonadEffects m where
    -- | Determine the absolute path of relative path in the current context
    makeAbsolutePath :: FilePath -> m FilePath
    findEnvPath :: String -> m FilePath

    -- | Having an explicit list of sets corresponding to the NIX_PATH
    -- and a file path try to find an existing path
    findPath :: [NThunk m] -> FilePath -> m FilePath

    pathExists :: FilePath -> m Bool
    importPath :: FilePath -> m (NValue m)
    pathToDefaultNix :: FilePath -> m FilePath

    getEnvVar :: String -> m (Maybe String)
    getCurrentSystemOS :: m Text
    getCurrentSystemArch :: m Text

    derivationStrict :: NValue m -> m (NValue m)

    nixInstantiateExpr :: String -> m (NValue m)

    getURL :: Text -> m (NValue m)

    getRecursiveSize :: a -> m (NValue m)

    traceEffect :: String -> m ()

    exec :: [String] -> m (NValue m)

class Monad m => MonadPutStr m where
    --TODO: Should this be used *only* when the Nix to be evaluated invokes a
    --`trace` operation?
    putStr :: String -> m ()
    default putStr :: (MonadTrans t, MonadPutStr m', m ~ t m') => String -> m ()
    putStr = lift . putStr

putStrLn :: MonadPutStr m => String -> m ()
putStrLn = putStr . (++"\n")

print :: (MonadPutStr m, Show a) => a -> m ()
print = putStrLn . show

instance MonadPutStr IO where
    putStr = Prelude.putStr

class Monad m => MonadStore m where
    -- | Import a path into the nix store, and return the resulting path
    addPath' :: FilePath -> m (Either ErrorCall StorePath)

    -- | Add a file with the given name and contents to the nix store
    toFile_' :: FilePath -> String -> m (Either ErrorCall StorePath)

instance MonadStore IO where
    addPath' path = do
        (exitCode, out, _) <-
            readProcessWithExitCode "nix-store" ["--add", path] ""
        case exitCode of
          ExitSuccess -> do
            let dropTrailingLinefeed p = take (length p - 1) p
            return $ Right $ StorePath $ dropTrailingLinefeed out
          _ -> return $ Left $ ErrorCall $
                  "addPath: failed: nix-store --add " ++ show path

    --TODO: Use a temp directory so we don't overwrite anything important
    toFile_' filepath content = do
      writeFile filepath content
      storepath <- addPath' filepath
      removeFile filepath
      return storepath

addPath :: (Framed e m, MonadStore m) => FilePath -> m StorePath
addPath p = either throwError return =<< addPath' p

toFile_ :: (Framed e m, MonadStore m) => FilePath -> String -> m StorePath
toFile_ p contents = either throwError return =<< toFile_' p contents
