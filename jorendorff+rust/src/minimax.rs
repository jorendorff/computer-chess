// *** minimax.rs: Generic minimax implementation *****************************

use std;
use std::thread;


// === What is a game?

pub trait Game : Clone {
    type Move : Copy;

    fn start() -> Self;
    fn moves(&self) -> Vec<Self::Move>;
    fn apply_move(&self, Self::Move) -> Self;

    // Returns >0.0 if the last move won the game, 0.0 for a draw.
    fn score_finished_game(&self) -> f64;
}


// === How to play a game, if you're a computer

fn max<T, I>(mut iter: I) -> T
    where I: Iterator<Item=T>, T: PartialOrd
{
    let first = iter.next().expect("max: empty iterator");
    iter.fold(first, |a, b| if a > b { a } else { b })
}

fn max_by<T, I, F, M>(mut iter: I, score: F) -> T
  where
    I: Iterator<Item=T>,
    F: Fn(&T) -> M,
    M: PartialOrd
{
    let init_value = iter.next().expect("max_by: empty iterator");
    let init_score = score(&init_value);
    let (max_value, _) = iter.fold((init_value, init_score), |(v1, s1), v2| {
        let s2 = score(&v2);
        if s2 > s1 { (v2, s2) } else { (v1, s1) }
    });
    max_value
}

pub fn best_move<G: Game>(game: &G) -> G::Move {
    *max_by(game.moves().iter(), |m| score_move(game, **m))
}

fn score_move<G: Game>(game: &G, m: G::Move) -> f64 {
    score_game(&game.apply_move(m))
}

fn score_game<G: Game>(game: &G) -> f64 {
    let moves = game.moves();
    if moves.len() == 0 {
        game.score_finished_game()
    } else {
        -max(moves.iter().map(|m| score_move(game, *m)))
    }
}


// === How to play a game when you are in a hurry

pub fn best_move_with_depth_limit<F, G>(estimator: &F, move_limit: i32, g: &G) -> G::Move where
    F: Fn(&G) -> f64, G: Game
{
    let halfmove_limit = move_limit * 2 - 1;
    let moves = g.moves();
    *max_by(moves.iter(), |m| score_move_with_depth_limit(estimator, halfmove_limit, g, **m))
}

fn score_move_with_depth_limit<F, G>(estimator: &F, halfmove_limit: i32, g: &G, m: G::Move) -> f64 where
    F: Fn(&G) -> f64, G: Game
{
    let g1 = g.apply_move(m);
    score_game_with_depth_limit(estimator, halfmove_limit, &g1)
}

fn score_game_with_depth_limit<F, G>(estimator: &F, halfmove_limit: i32, g: &G) -> f64 where
    F: Fn(&G) -> f64, G: Game
{
    let moves = g.moves();
    if moves.len() == 0 {
        g.score_finished_game()
    } else if halfmove_limit == 0 {
        estimator(g)
    } else {
        -0.999 * max(moves.iter().map(|m| {
            score_move_with_depth_limit(estimator, halfmove_limit - 1, g, *m)
        }))
    }
}


// === ...and you have threads available

pub fn best_move_with_depth_limit_threaded<F, G>(estimator: &F, move_limit: i32, g: &G)
        -> std::thread::Result<G::Move> where
    F: 'static + Copy + Send + Fn(&G) -> f64,
    G: 'static + Game + Send,
    G::Move: 'static + Send
{
    let halfmove_limit = move_limit * 2 - 1;
    let moves: Vec<_> = g.moves();
    let mut threads: Vec<std::thread::JoinHandle<(G::Move, f64)>> = vec![];

    for m in moves {
        let child_estimator: F = *estimator;
        let game: G = g.clone();
        let handle = thread::spawn(move || {
            (m, score_move_with_depth_limit(&child_estimator, halfmove_limit, &game, m))
        });
        threads.push(handle);
    }

    let mut best_move = None;
    let mut best_score = std::f64::NEG_INFINITY;
    for t in threads {
        let (m, score) = try!(t.join());
        if score > best_score {
            best_move = Some(m);
            best_score = score;
        }
    }

    Ok(best_move.expect("there should have been at least one move"))
}
