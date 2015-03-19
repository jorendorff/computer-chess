module XBoard(playXBoard) where

import Control.Monad(forever)
import Control.Monad.State(StateT, liftIO, put, get, runStateT)
import System.IO(hFlush, stdout)
import System.Exit(exitWith, ExitCode(ExitSuccess))
import Data.Char(isSpace, ord)
import Data.Bits(bit, (.|.))
import Minimax(start, moves, applyMove)
import Chess(Chessboard(..), ChessMove, ChessColor(White, Black), chessAI)

data MoveResult = MoveError String | GameOver String | Continue Chessboard

tryMove :: Chessboard -> String -> MoveResult
tryMove board str = case reads str of
  [] -> MoveError ("unrecognized move: " ++ str)
  (move, rest) : _ ->
    if not (all isSpace rest)
    then MoveError("unrecognized move: " ++ str)
    else if not (elem move (moves board))
         then MoveError ("illegal move: " ++ show move)
         else let result = applyMove board move
              in Continue result -- we are not good at figuring out when the game is over, sorry

ignoredCommands = [
  "xboard", "accepted", "rejected", "variant", "random", "force", "white", "black", "level",
  "st", "sd", "nps", "time", "otim", "?", "ping", "draw", "result", "edit", "hint", "bk", "undo",
  "remove", "hard", "easy", "post", "nopost", "analyze", "name", "rating", "computer", "option"]

respond :: String -> StateT a IO ()
respond str = liftIO $ do
  putStrLn str
  hFlush stdout
  appendFile "xboard-input.txt" $ (concat $ map ("<-- " ++) (lines str)) ++ "\n"

say str = liftIO $ appendFile "xboard-input.txt" str

fileToInt :: Char -> Int
fileToInt file = (ord file) - (ord 'a')

fenToBoard :: String -> Chessboard
fenToBoard str = Chessboard {
  bPawns   = bitBoard "p",
  bKnights = bitBoard "n",
  bBishops = bitBoard "bq",
  bRooks   = bitBoard "rq",
  bKing    = bitBoard "k",
  wPawns   = bitBoard "P",
  wKnights = bitBoard "N",
  wBishops = bitBoard "BQ",
  wRooks   = bitBoard "RQ",
  wKing    = bitBoard "K",
  whoseTurn = whoseTurn}
  where
    [piecesStr, whoseTurnStr, castlingString, enPassantString] = words str

    bitBoard chars = foldr (.|.) 0
                     $ map (\(c, b) -> if c `elem` chars then b else 0)
                     $ zip array (map bit [0..63])

    array = concat $ reverse $ splitLength 8
            $ filter (/= '/') $ expandSpaces piecesStr

    expandSpaces :: String -> String
    expandSpaces (x:xs)
        | x `elem` ['1'..'8'] = (replicate (read [x]) ' ') ++ (expandSpaces xs)
        | otherwise = x:(expandSpaces xs)
    expandSpaces "" = ""

    splitLength n xs@(x:_) = take n xs : (splitLength n $ drop n xs)
    splitLength _ [] = []
    whoseTurn = case whoseTurnStr of
                  "w" -> White
                  "b" -> Black
    bCastleL = 'q' `elem` castlingString
    bCastleR = 'k' `elem` castlingString
    wCastleL = 'Q' `elem` castlingString
    wCastleR = 'K' `elem` castlingString
    enPassantFile
      | enPassantString == "-" = (-1)
      | otherwise = fileToInt $ head enPassantString

go ai = do
  board <- get
  let move = ai board
  respond $ "move " ++ (show move)
  put $ applyMove board move


commandLoop :: (Chessboard -> ChessMove) -> StateT Chessboard IO ()
commandLoop ai = forever $ do
  thisLine <- liftIO getLine
  let command = head $ words thisLine
  let arguments = drop ((length command) + 1) thisLine
  say $ "--> " ++ thisLine ++ "\n"                           
  if command `elem` ignoredCommands
  then return ()
  else case command of
    "new"      -> put start
    "protover" -> respond $ "feature variants=\"normal\" usermove=1 draw=0 analyze=0 colors=0 setboard=1 sigint=0 done=1"
    "quit"     -> liftIO $ exitWith ExitSuccess
    "setboard" -> do
      say arguments
      let boardNow = fenToBoard arguments
      put $ boardNow
      say $ show boardNow
    "go" -> do
      go ai
      boardNow <- get
      say $ show boardNow
    "usermove" -> do
      boardBefore <- get
      case tryMove boardBefore arguments of
        MoveError msg -> respond msg
        GameOver msg -> respond msg
        Continue board' -> do
          put board'
          go ai
      boardNow <- get
      say $ show boardNow
    _ -> respond $ "Error: (unknown command): " ++ thisLine

playXBoard :: (Chessboard -> ChessMove) -> IO ()
playXBoard ai = do
  runStateT (commandLoop ai) start
  return ()
