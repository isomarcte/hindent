{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Main entry point to hindent.
--
-- hindent

module Main where

import           HIndent
import           HIndent.Types

import           Control.Applicative
import           Data.List
import           Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy.Builder as T
import qualified Data.Text.Lazy.IO as T
import           Data.Version (showVersion)
import           Descriptive
import           Descriptive.Options
import           GHC.Tuple
import           Language.Haskell.Exts hiding (Style,style)
import           Paths_hindent (version)
import           System.Directory
import           System.Environment
import           System.IO
import           Text.Read
import           Control.Exception
import           GHC.IO.Exception
import           Foreign.C.Error

-- | Main entry point.
main :: IO ()
main =
  do args <- getArgs
     case consume options (map T.pack args) of
       Succeeded (style,exts,mfilepath) ->
         case mfilepath of
           Just filepath ->
             do text <- T.readFile filepath
                tmpDir <- getTemporaryDirectory
                (fp,h) <- openTempFile tmpDir "hindent.hs"
                T.hPutStrLn
                  h
                  (either error T.toLazyText (reformat style (Just exts) text))
                hFlush h
                hClose h
                let exdev e = if ioe_errno e == Just ((\(Errno a) -> a) eXDEV)
                                  then copyFile fp filepath >> removeFile fp
                                  else throw e
                renameFile fp filepath `catch` exdev
           Nothing ->
             T.interact (either error T.toLazyText . reformat style (Just exts))
       Failed (Wrap (Stopped Version) _) ->
         putStrLn ("hindent " ++ showVersion version)
       _ ->
         error (T.unpack (textDescription (describe options [])))

-- | Options that stop the argument parser.
data Stoppers = Version
  deriving (Show)

-- | Program options.
options :: Monad m
        => Consumer [Text] (Option Stoppers) m (Style,[Extension],Maybe FilePath)
options =
  ver *>
  ((,,) <$> style <*> exts <*> file)
  where ver =
          stop (flag "version" "Print the version" Version)
        style =
          makeStyle johanTibell <$> lineLen
        exts =
          fmap getExtensions (many (prefix "X" "Language extension"))
        lineLen =
          fmap (>>= (readMaybe . T.unpack))
               (optional (arg "line-length" "Desired length of lines"))
        makeStyle s mlen =
          case mlen of
            Nothing -> s
            Just len ->
              s {styleDefConfig =
                   (styleDefConfig s) {configMaxColumns = len}}
        file = fmap (fmap T.unpack) (optional (anyString "[<filename>]"))

--------------------------------------------------------------------------------
-- Extensions stuff stolen from hlint

-- | Consume an extensions list from arguments.
getExtensions :: [Text] -> [Extension]
getExtensions = foldl f defaultExtensions . map T.unpack
  where f _ "Haskell98" = []
        f a ('N':'o':x)
          | Just x' <- readExtension x =
            delete x' a
        f a x
          | Just x' <- readExtension x =
            x' :
            delete x' a
        f _ x = error $ "Unknown extension: " ++ x

-- | Parse an extension.
readExtension :: String -> Maybe Extension
readExtension x =
  case classifyExtension x of
    UnknownExtension _ -> Nothing
    x' -> Just x'
