import Foundation

// murmur-eval: scores Murmur's speech engines on the owner's own recordings. See evals/README.md.
let exitCode = await EvalCLI.run(Array(CommandLine.arguments.dropFirst()))
exit(exitCode)
