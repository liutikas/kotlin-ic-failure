# IC failure Reproducer: `The following FqNames can't be derived from DirtyData.dirtyLookupSymbols`

Minimal standalone Gradle reproducer for [KT-84271](https://youtrack.jetbrains.com/issue/KT-84271), where Kotlin JVM incremental compilation fails with:

```text
Caused by: org.jetbrains.kotlin.gradle.tasks.CompilationErrorException: Incremental compilation failed: The following FqNames can't be derived from DirtyData.dirtyLookupSymbols: com.example.lib.Outer.
DirtyData = DirtyData(dirtyLookupSymbols=[LookupSymbol(name=create, scope=com.example.lib.Outer.Companion), LookupSymbol(name=Companion, scope=com.example.lib.Outer), LookupSymbol(name=<SAM-CONSTRUCTOR>, scope=com.example.lib.Outer.Companion), LookupSymbol(name=<SAM-CONSTRUCTOR>, scope=com.example.lib.Outer)], dirtyClassesFqNames=[com.example.lib.Outer, com.example.lib.Outer.Companion], dirtyClassesFqNamesForceRecompile=[])
java.lang.IllegalStateException: The following FqNames can't be derived from DirtyData.dirtyLookupSymbols: com.example.lib.Outer.
	at org.jetbrains.kotlin.incremental.classpathDiff.ClasspathChangesComputer.toProgramSymbols(ClasspathChangesComputer.kt:386)
	at org.jetbrains.kotlin.incremental.classpathDiff.ClasspathChangesComputer.computeFineGrainedKotlinClassChanges(ClasspathChangesComputer.kt:286)
```

## How to Reproduce

Run:

```bash
./reproduce.sh
```

By default, the build uses Kotlin `2.4.21` (configurable via `-PkotlinVersion=<version>`):

- **Kotlin `2.4.20` / `2.4.21` (Fails the Gradle build):**
  ```bash
  ./reproduce.sh -PkotlinVersion=2.4.21
  ```
- **Kotlin `2.3.20` (Throws the same `IllegalStateException` in IC, but silently falls back to non-incremental compilation and succeeds):**
  ```bash
  ./reproduce.sh -PkotlinVersion=2.3.20 --info
  ```

## What Happens Step by Step

1. **Step 1 (Clean build):**
   - `:lib` defines `com.example.lib.Outer` with a `companion object { fun create(): Int = 1 }`.
   - `:app` directly imports the companion member (`import com.example.lib.Outer.Companion.create`) and calls `create()` without referencing `Outer` directly.
   - During FIR import resolution (`FirImportResolveTransformer.transformImport`), only `recordFqNameLookup(FqName("com.example.lib.Outer.Companion.create"))` is recorded (`LookupSymbol(name = "create", scope = "com.example.lib.Outer.Companion")`). No lookup symbol is recorded for `Outer` (`LookupSymbol(name = "Outer", scope = "com.example.lib")`) or `LookupSymbol(name = "Companion", scope = "com.example.lib.Outer")`.
   - When `ClasspathSnapshotShrinker` shrinks `:app`'s classpath snapshot:
     - `com/example/lib/Outer$Companion` **is retained** because `lookupSymbols.getLookupNamesInScope(FqName("com.example.lib.Outer.Companion"))` is non-empty.
     - `com/example/lib/Outer` **is dropped** because `Outer` is not in `lookupSymbols` and `ConstantsInCompanionObjectsImpact` only adds an impact edge from `Outer.Companion -> Outer` when the companion object declares `const val` constants.

2. **Step 2 (Incremental build):**
   - `Outer.Companion` is removed in `:lib` (or whenever `Outer.Companion` is present in `changedPreviousClasses` XOR `changedCurrentClasses` while `Outer` is absent from `changedPreviousClasses + changedCurrentClasses`).
   - During `:app:compileKotlin` classpath diffing (`ClasspathChangesComputer.computeFineGrainedKotlinClassChanges`):
     1. `ChangesCollector.collectProtoChanges(oldData = Outer.Companion, newData = null)` calls `oldData.collectAllFromClass(isRemoved = true)`.
     2. Because `proto.isCompanionObject` is `true`, `ChangesCollector.collectAllFromClass` calls:
        ```kotlin
        collectMember(classFqName.parent(), classFqName.shortName().asString())
        ```
        which adds `LookupSymbol(name = "Companion", scope = "com.example.lib.Outer")` to `dirtyLookupSymbols` and `FqName("com.example.lib.Outer")` to `dirtyClassesFqNames`.
     3. `DirtyData.toProgramSymbols(allClasses)` attempts to match `dirtyLookupSymbols` and `dirtyClassesFqNames` against `allClasses` (`fineGrainedCurrentClassSnapshots + fineGrainedPreviousClassSnapshots`).
     4. Because `com.example.lib.Outer` is not in `allClasses`, `com.example.lib.Outer` remains in `unmatchedFqNames`, triggering:
        ```text
        IllegalStateException: The following FqNames can't be derived from DirtyData.dirtyLookupSymbols: com.example.lib.Outer
        ```

3. **Why this became a build-breaking error in 2.4.x:**
   - In `2.3.20`, `CompileServiceImpl.execIncrementalCompiler` caught the `IllegalStateException`, reported `ReportSeverity.ERROR` via `ICReporterBase.reportCompileIteration`, and fell back to `execNonIncrementalCompiler`, which returned `ExitCode.OK`. Because `KotlinLoggerMessageCollectorAdapter` only logged the message without failing the worker, the fallback succeeded.
   - Starting in `2.4.0-Beta1` / `2.4.20` / `2.4.21` (commit `bc1756f32dd0` for [KT-85061](https://youtrack.jetbrains.com/issue/KT-85061)), `BuildToolsApiCompilationWork` buffers all compiler diagnostics in `ProblemsApiCompilerMessageRenderer` and replays them in `finally` via `DefaultCompilerDiagnosticsProblemsReporter.reportCompilerMessage`. Any `CompilerMessageSeverity.ERROR` message—including `Incremental compilation failed: ...` emitted before the non-incremental fallback—now throws `CompilationErrorException`, failing the Gradle task even when the non-incremental fallback compilation succeeds.
