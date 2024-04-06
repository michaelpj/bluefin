module Bluefin.Compound
  ( -- * Creating your own effects

    -- ** Wrap a single effect

    -- | Because in Bluefin everything happens at the value level,
    -- creating your own effects is equivalent to creating your own
    -- data types.  We just use the techniques we know and love from
    -- Haskell!  For example, if I want to make a "counter" effect
    -- that allows me to increment a counter then I can wrap a @State@
    -- handle in a newtype:
    --
    -- @
    -- newtype Counter1 e = MkCounter1 (State Int e)
    --
    -- incCounter1 :: (e :> es) => Counter1 e -> Eff es ()
    -- incCounter1 (MkCounter1 st) = modify st (+ 1)
    --
    -- runCounter1 ::
    --   (forall e. Counter1 e -> Eff (e :& es) r) ->
    --   Eff es Int
    -- runCounter1 k =
    --   evalState 0 $ \\st -> do
    --     _ <- k (MkCounter1 st)
    --     get st
    -- @
    --
    -- Running the handler tells me the number of times I incremented
    -- the counter.
    --
    -- @
    -- exampleCounter1 :: Int
    -- exampleCounter1 = runPureEff $ runCounter1 $ \\c ->
    --   incCounter1 c
    --   incCounter1 c
    --   incCounter1 c
    -- @
    --
    -- @
    -- >>> exampeleCounter1
    -- 3
    -- @

    -- ** Wrap multiple effects, first attempt

    -- | If we want to wrap multiple effects then we can use the
    -- normal approach we use to wrap multiple values into a single
    -- value: define a new data type with multiple fields.  There's a
    -- caveat to this approach, but before we address the caveat let's
    -- see the approach in action.  Here we define a new handle,
    -- @Counter2@, that contains a @State@ and @Exception@ handle
    -- within it.  That allows us to increment the counter and throw
    -- an exception when we hit a limit.
    --
    -- @
    -- data Counter2 e1 e2 = MkCounter2 (State Int e1) (Exception () e2)
    --
    -- incCounter2 :: (e1 :> es, e2 :> es) => Counter2 e1 e2 -> Eff es ()
    -- incCounter2 (MkCounter2 st ex) = do
    --   count <- get st
    --   when (count >= 10) $
    --     throw ex ()
    --   put st (count + 1)
    --
    -- runCounter2 ::
    --   (forall e1 e2. Counter2 e1 e2 -> Eff (e2 :& e1 :& es) r) ->
    --   Eff es Int
    -- runCounter2 k =
    --   evalState 0 $ \\st -> do
    --     _ \<- try $ \\ex -> do
    --       k (MkCounter2 st ex)
    --     get st
    -- @
    --
    -- We can see that attempting to increment the counter fovever
    -- bails out when we reach the limit.
    --
    -- @
    -- exampleCounter2 :: Int
    -- exampleCounter2 = runPureEff $ runCounter2 $ \\c ->
    --   forever $
    --     incCounter2 c
    -- @
    --
    -- @
    -- >>> exampleCounter2
    -- 10
    -- @
    --
    -- The flaw of this approach is that you expose one effect
    -- parameter for each handle in the data type.  That's rather
    -- cumbersome!  We can do better.

    -- ** Wrap multiple effects, a better approach

    -- | We can avoid exposing multiple effect parameters and just
    -- expose a single one.  To make this work we have to define our
    -- handler in a slightly different way.  Firstly we apply
    -- @useImplIn@ to the effectful operation @k@ and secondly we
    -- apply @mapHandle@ to each of the handles out of which we create
    -- our compound handle.  Everything else remains the same.
    --
    -- @
    -- data Counter3 e = MkCounter3 (State Int e) (Exception () e)
    --
    -- incCounter3 :: (e :> es) => Counter3 e -> Eff es ()
    -- incCounter3 (MkCounter3 st ex) = do
    --   count <- get st
    --   when (count >= 10) $
    --     throw ex ()
    --   put st (count + 1)
    --
    -- runCounter3 ::
    --   (forall e. Counter3 e -> Eff (e :& es) r) ->
    --   Eff es Int
    -- runCounter3 k =
    --   evalState 0 $ \\st -> do
    --     _ \<- try $ \\ex -> do
    --       useImplIn k (MkCounter3 (mapHandle st) (mapHandle ex))
    --     get st
    -- @
    --
    -- The example works as before:
    --
    -- @
    -- exampleCounter3 :: Int
    -- exampleCounter3 = runPureEff $ runCounter3 $ \\c ->
    --   forever $
    --     incCounter3 c
    -- @
    --
    -- @
    -- >>> exampleCounter3
    -- 10
    -- @

    -- ** Wrap multiple effects, don't handle them all

    -- | So far our handlers have handled all the effects that are
    -- found within our compound effect. We don't have to do that
    -- though: we can leave some of the effects unhandled to be
    -- handled by a different handler at a higher level.  Let's extend
    -- our example with a @Stream@ effect.  Whenever we ask to
    -- increment the counter, and it is currently an even number, then
    -- we yield a message about that.  Additionally, there's a new
    -- operation @getCounter4@ which allows us to yield a message
    -- whilst returning the value of the counter.
    --
    -- @
    -- data Counter4 e
    --   = MkCounter4 (State Int e) (Exception () e) (Stream String e)
    --
    -- incCounter4 :: (e :> es) => Counter4 e -> Eff es ()
    -- incCounter4 (MkCounter4 st ex y) = do
    --   count <- get st
    --
    --   when (even count) $
    --     yield y "Count was even"
    --
    --   when (count >= 10) $
    --     throw ex ()
    --
    --   put st (count + 1)
    --
    -- getCounter4 :: (e :> es) => Counter4 e -> String -> Eff es Int
    -- getCounter4 (MkCounter4 st _ y) msg = do
    --   yield y msg
    --   get st
    --
    -- runCounter4 ::
    --   (e1 :> es) =>
    --   Stream String e1 ->
    --   (forall e. Counter4 e -> Eff (e :& es) r) ->
    --   Eff es Int
    -- runCounter4 y k =
    --   evalState 0 $ \\st -> do
    --     _ \<- try $ \\ex -> do
    --       useImplIn k (MkCounter4 (mapHandle st) (mapHandle ex) (mapHandle y))
    --     get st
    -- @
    --
    -- @
    -- exampleCounter4 :: ([String], Int)
    -- exampleCounter4 = runPureEff $ yieldToList $ \\y -> do
    --   runCounter4 y $ \\c -> do
    --     incCounter4 c
    --     incCounter4 c
    --     n <- getCounter4 c "I'm getting the counter"
    --     when (n == 2) $
    --       yield y "n was 2, as expected"
    -- @
    --
    -- @
    -- >>> exampleCounter4
    -- (["Count was even","I'm getting the counter","n was 2, as expected"],2)
    -- @

    -- ** Dynamic effects

    -- | So far we've looked at "concrete" compound effects, that is,
    -- new effects implemented in terms of specific other effects.  We
    -- can also define dynamic effects, whose implementation is left
    -- abstract, to be defined in the handler.  To do that we create a
    -- handle that is a record of functions.  To run an effectful
    -- operation we call one of the functions from the record.  We
    -- define the record in the handler.  Here @incCounter5Impl@ and
    -- @getCounter5Impl@ are exactly the same as @incCounter4@ and
    -- @getCounter4@ were, they're just defined in the handler.  In
    -- order to be used polymorphically, the actually effectful
    -- functions we call, @incCounter5@ and @getCounter5@ are derived
    -- from the record fields by applying @useImpl@.
    --
    -- @
    -- data Counter5 e = MkCounter5
    --   { incCounter5Impl :: Eff e (),
    --     getCounter5Impl :: String -> Eff e Int
    --   }
    --
    -- incCounter5 :: (e :> es) => Counter5 e -> Eff es ()
    -- incCounter5 e = useImpl (incCounter5Impl e)
    --
    -- getCounter5 :: (e :> es) => Counter5 e -> String -> Eff es Int
    -- getCounter5 e msg = useImpl (getCounter5Impl e msg)
    --
    -- runCounter5 ::
    --   (e1 :> es) =>
    --   Stream String e1 ->
    --   (forall e. Counter5 e -> Eff (e :& es) r) ->
    --   Eff es Int
    -- runCounter5 y k =
    --   evalState 0 $ \\st -> do
    --     _ \<- try $ \\ex -> do
    --       useImplIn
    --         k
    --         ( MkCounter5
    --             { incCounter5Impl = do
    --                 count <- get st
    --
    --                 when (even count) $
    --                   yield y "Count was even"
    --
    --                 when (count >= 10) $
    --                   throw ex ()
    --
    --                 put st (count + 1),
    --               getCounter5Impl = \\msg -> do
    --                 yield y msg
    --                 get st
    --             }
    --         )
    --     get st
    -- @
    --
    -- The result is exactly the same as before
    --
    -- @
    -- exampleCounter5 :: ([String], Int)
    -- exampleCounter5 = runPureEff $ yieldToList $ \\y -> do
    --   runCounter5 y $ \\c -> do
    --     incCounter5 c
    --     incCounter5 c
    --     n <- getCounter5 c "I'm getting the counter"
    --     when (n == 2) $
    --       yield y "n was 2, as expected"
    -- @
    --
    -- @
    -- >>> exampleCounter5
    -- (["Count was even","I'm getting the counter","n was 2, as expected"],2)
    -- @

    -- ** Combining concrete and dynamic effects

    -- | We can also freely combine concrete and dynamic effects.  In
    -- the following example, the @incCounter6@ effect is left
    -- dynamic, and defined in the handler, whilst @getCounter6@ is
    -- implemented in terms of concrete @State@ and @Stream@ effects.
    --
    -- @
    -- data Counter6 e = MkCounter6
    --   { incCounter6Impl :: Eff e (),
    --     counter6State :: State Int e,
    --     counter6Stream :: Stream String e
    --   }
    --
    -- incCounter6 :: (e :> es) => Counter6 e -> Eff es ()
    -- incCounter6 e = useImpl (incCounter6Impl e)
    --
    -- getCounter6 :: (e :> es) => Counter6 e -> String -> Eff es Int
    -- getCounter6 (MkCounter6 _ st y) msg = do
    --   yield y msg
    --   get st
    --
    -- runCounter6 ::
    --   (e1 :> es) =>
    --   Stream String e1 ->
    --   (forall e. Counter6 e -> Eff (e :& es) r) ->
    --   Eff es Int
    -- runCounter6 y k =
    --   evalState 0 $ \\st -> do
    --     _ \<- try $ \\ex -> do
    --       useImplIn
    --         k
    --         ( MkCounter6
    --             { incCounter6Impl = do
    --                 count <- get st
    --
    --                 when (even count) $
    --                   yield y "Count was even"
    --
    --                 when (count >= 10) $
    --                   throw ex ()
    --
    --                 put st (count + 1),
    --               counter6State = mapHandle st,
    --               counter6Stream = mapHandle y
    --             }
    --         )
    --     get st
    -- @
    --
    -- Naturally, the result is the same.
    --
    -- @
    -- exampleCounter6 :: ([String], Int)
    -- exampleCounter6 = runPureEff $ yieldToList $ \\y -> do
    --   runCounter6 y $ \\c -> do
    --     incCounter6 c
    --     incCounter6 c
    --     n <- getCounter6 c "I'm getting the counter"
    --     when (n == 2) $
    --       yield y "n was 2, as expected"
    -- @
    --
    -- @
    -- >>> exampleCounter6
    -- (["Count was even","I'm getting the counter","n was 2, as expected"],2)
    -- @

    -- ** A dynamic file system effect

    -- | The @effectful@ library has [an example of a dynamic effect
    -- for basic file system
    -- access](https://hackage.haskell.org/package/effectful-core-2.2.1.0/docs/Effectful-Dispatch-Dynamic.html#g:2).
    -- This is what it looks like in Bluefin.  We start by defining a
    -- record of effectful operations.
    --
    -- @
    -- data FileSystem es = MkFileSystem
    --   { readFileImpl :: FilePath -> Eff es String,
    --     writeFileImpl :: FilePath -> String -> Eff es ()
    --   }
    --
    -- readFile :: (e :> es) => FileSystem e -> FilePath -> Eff es String
    -- readFile fs filepath = useImpl (readFileImpl fs filepath)
    --
    -- writeFile :: (e :> es) => FileSystem e -> FilePath -> String -> Eff es ()
    -- writeFile fs filepath contents = useImpl (writeFileImpl fs filepath contents)
    -- @
    --
    -- We can make a pure handler that simulates reading and writing
    -- to a file system by storing file contents in an association
    -- list.
    --
    -- @
    -- runFileSystemPure ::
    --   (e1 :> es) =>
    --   Exception String e1 ->
    --   [(FilePath, String)] ->
    --   (forall e2. FileSystem e2 -> Eff (e2 :& es) r) ->
    --   Eff es r
    -- runFileSystemPure ex fs0 k =
    --   evalState fs0 $ \\fs ->
    --     useImplIn
    --       k
    --       MkFileSystem
    --         { readFileImpl = \\filepath -> do
    --             fs' <- get fs
    --             case lookup filepath fs' of
    --               Nothing ->
    --                 throw ex ("File not found: " <> filepath)
    --               Just s -> pure s,
    --           writeFileImpl = \\filepath contents ->
    --             modify fs ((filepath, contents) :)
    --         }
    -- @
    --
    -- Or we can make a handler that actually performs IO operations
    -- against a real file system.
    --
    -- @
    -- runFileSystemIO ::
    --   forall e1 e2 es r.
    --   (e1 :> es, e2 :> es) =>
    --   Exception String e1 ->
    --   IOE e2 ->
    --   (forall e. FileSystem e -> Eff (e :& es) r) ->
    --   Eff es r
    -- runFileSystemIO ex io k =
    --   useImplIn
    --     k
    --     MkFileSystem
    --       { readFileImpl =
    --           adapt . Prelude.readFile,
    --         writeFileImpl =
    --           \\filepath -> adapt . Prelude.writeFile filepath
    --       }
    --   where
    --     adapt :: (e1 :> ess, e2 :> ess) => IO a -> Eff ess a
    --     adapt m =
    --       effIO io (Control.Exception.try @IOException m) >>= \\case
    --         Left e -> throw ex (show e)
    --         Right r -> pure r
    -- @
    --
    -- We can use the @FileSystem@ effect to define an action which
    -- does some file system operations.
    --
    -- @
    -- action :: (e :> es) => FileSystem e -> Eff es String
    -- action fs = do
    --   file <- readFile fs "\/dev\/null"
    --   when (length file == 0) $ do
    --     writeFile fs "\/tmp\/bluefin" "Hello!"
    --   readFile fs "\/tmp\/doesn't exist"
    -- @
    --
    -- and we can run it purely, against a simulated file system
    --
    -- @
    -- exampleRunFileSystemPure :: Either String String
    -- exampleRunFileSystemPure = runPureEff $ try $ \\ex ->
    --   runFileSystemPure ex [("\/dev\/null", "")] action
    -- @
    --
    -- @
    -- >>> exampleRunFileSystemPure
    -- Left "File not found: \/tmp\/doesn't exist"
    -- @
    --
    -- or against the real file system.
    --
    -- @
    -- exampleRunFileSystemIO :: IO (Either String String)
    -- exampleRunFileSystemIO = runEff $ \\io -> try $ \\ex ->
    --   runFileSystemIO ex io action
    -- @
    --
    -- @
    -- >>> exampleRunFileSystemIO
    -- Left "\/tmp\/doesn't exist: openFile: does not exist (No such file or directory)"
    -- \$ cat \/tmp\/bluefin
    -- Hello!
    -- @

    -- * Functions for making compound effects

    Handle (mapHandle),
    useImpl,
    useImplIn,

    -- * Deprecated

    -- | Do not use.  Will be removed in a future version.

    Compound,
    runCompound,
    withCompound,
  )
where

import Bluefin.Internal
