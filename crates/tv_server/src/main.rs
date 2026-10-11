// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_server.md, section "main.rs"
// ============================================================================

//! Headless server entry point. Only the deterministic self-test exists so far.

use std::process::ExitCode;
use tv_sim::testkit::{scripted_commands, synthetic_chem};
use tv_sim::{SplitMix64, World};

const USAGE: &str = "usage: tv_server selftest [--seed N] [--ticks N]\n       tv_server serve";

fn parse_flag(args: &[String], name: &str, default: u64) -> Result<u64, String> {
    match args.iter().position(|a| a == name) {
        None => Ok(default),
        Some(i) => args
            .get(i + 1)
            .ok_or_else(|| format!("{name} needs a value"))?
            .parse()
            .map_err(|_| format!("{name} must be a non-negative integer")),
    }
}

/// Runs the scripted simulation and prints one line. Two runs with the same
/// arguments must print the same line, byte for byte.
fn selftest(seed: u64, ticks: u64) {
    let mut world = World::new(seed, synthetic_chem(16, 7));
    let mut script = SplitMix64::new(seed ^ 0xA5A5);
    let mut detonations = 0usize;
    for t in 0..ticks as u32 {
        let cmds = scripted_commands(&mut script, t, 4, 16);
        world.step(&cmds);
        detonations += world.drain_events().len();
    }
    println!(
        "selftest seed={seed} ticks={ticks} hash={:#018x} detonations={detonations} rejected={} in_flight={}",
        world.state_hash(),
        world.rejected(),
        world.balloon_count()
    );
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("selftest") => match (
            parse_flag(&args, "--seed", 1),
            parse_flag(&args, "--ticks", 3600),
        ) {
            (Ok(seed), Ok(ticks)) => {
                selftest(seed, ticks);
                ExitCode::SUCCESS
            }
            (Err(e), _) | (_, Err(e)) => {
                eprintln!("error: {e}\n{USAGE}");
                ExitCode::from(2)
            }
        },
        Some("serve") => {
            eprintln!("error: networking is not implemented yet (see docs/OPEN_DECISIONS.md)");
            ExitCode::from(2)
        }
        _ => {
            eprintln!("{USAGE}");
            ExitCode::from(2)
        }
    }
}
