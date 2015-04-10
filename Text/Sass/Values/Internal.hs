module Text.Sass.Values.Internal
  (
    toNativeValue
  , fromNativeValue
  , deleteNativeValue
  , makeValueForeignPtr
  ) where

import qualified Binding.Libsass     as Lib
import           Control.Applicative ((<$>))
import           Control.Monad       (forM, zipWithM_, (>=>))
import           Foreign
import           Foreign.C
import           Text.Sass.Values

-- | Converts a 'SassValue' to native type.
--
--   This is (mostly) internal function.
toNativeValue :: SassValue -> IO (Ptr Lib.SassValue)
toNativeValue (SassBool val) = Lib.sass_make_boolean val
toNativeValue (SassNumber val unit) = withCString unit $
    Lib.sass_make_number (realToFrac val)
toNativeValue (SassColor r g b a) = Lib.sass_make_color r' g' b' a'
    where r' = realToFrac r
          g' = realToFrac g
          b' = realToFrac b
          a' = realToFrac a
toNativeValue (SassString str) = withCString str Lib.sass_make_string
toNativeValue SassNull = Lib.sass_make_null
toNativeValue (SassWarning str) = withCString str Lib.sass_make_warning
toNativeValue (SassError str) = withCString str Lib.sass_make_error
toNativeValue (SassList lst sep') = do
    let len = fromIntegral $ length lst
    let sep = fromIntegral $ fromEnum sep'
    result <- Lib.sass_make_list len sep
    zipWithM_ (addToList result) lst [0..len - 1]
    return result
    where
        addToList list e idx = do
            native <- toNativeValue e
            Lib.sass_list_set_value list idx native

toNativeValue (SassMap lst) = do
    let len = fromIntegral $ length lst
    result <- Lib.sass_make_map len
    zipWithM_ (addToMap result) lst [0..len - 1]
    return result
    where
        addToMap list (key, val) idx = do
            nativeKey <- toNativeValue key
            nativeVal <- toNativeValue val
            Lib.sass_map_set_key list idx nativeKey
            Lib.sass_map_set_value list idx nativeVal

-- | Converts native value to 'SassValue'.
--
--   This is (mostly) internal function.
fromNativeValue :: Ptr Lib.SassValue -> IO SassValue
fromNativeValue ptr = do
    tag <- Lib.sass_value_get_tag ptr
    fromNativeValue' (toEnum $ fromIntegral tag) ptr

-- | Real code for 'fromNativeValue'.
fromNativeValue' :: Lib.SassTag -> Ptr Lib.SassValue -> IO SassValue
fromNativeValue' Lib.SassBoolean ptr =
    SassBool <$> Lib.sass_boolean_get_value ptr
fromNativeValue' Lib.SassNumber ptr = do
    val <- Lib.sass_number_get_value ptr
    unit <- Lib.sass_number_get_unit ptr >>= peekCString
    return $ SassNumber (realToFrac val) unit
fromNativeValue' Lib.SassColor ptr = do
    r <- realToFrac <$> Lib.sass_color_get_r ptr
    g <- realToFrac <$> Lib.sass_color_get_g ptr
    b <- realToFrac <$> Lib.sass_color_get_b ptr
    a <- realToFrac <$> Lib.sass_color_get_a ptr
    return $ SassColor r g b a
fromNativeValue' Lib.SassString ptr =
    SassString <$> (Lib.sass_string_get_value ptr >>= peekCString)
fromNativeValue' Lib.SassNull _ = return SassNull
fromNativeValue' Lib.SassWarning ptr = do
    SassWarning <$> (Lib.sass_warning_get_message ptr >>= peekCString)
fromNativeValue' Lib.SassError ptr = do
    SassError <$> (Lib.sass_error_get_message ptr >>= peekCString)
fromNativeValue' Lib.SassList ptr = do
    len <- Lib.sass_list_get_length ptr
    sep <- fromIntegral <$> Lib.sass_list_get_separator ptr
    lst <- forM [0..len - 1] (Lib.sass_list_get_value ptr >=> fromNativeValue)
    return $ SassList lst (toEnum sep)

fromNativeValue' Lib.SassMap ptr = do
    len <- Lib.sass_map_get_length ptr
    lst <- forM [0..len - 1] $ \idx -> do
        key <- Lib.sass_map_get_key ptr idx >>= fromNativeValue
        val <- Lib.sass_map_get_value ptr idx >>= fromNativeValue
        return (key, val)
    return $ SassMap lst

-- | Frees native representation of 'SassValue'.
--
--   This is (mostly) internal function.
deleteNativeValue :: Ptr Lib.SassValue -> IO ()
deleteNativeValue = Lib.sass_delete_value

-- | Makes 'ForeignPtr' from 'Ptr' to native representation of 'SassValue'.
--
--   This is (mostly) internal function.
makeValueForeignPtr :: Ptr Lib.SassValue -> IO (ForeignPtr Lib.SassValue)
makeValueForeignPtr = newForeignPtr Lib.p_sass_delete_value
