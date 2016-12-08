import os

import compiler/vm
import compiler/ast
import compiler/sem
import compiler/msgs
import compiler/vmdef
import compiler/lists
import compiler/idents
import compiler/passes
import compiler/nimconf
import compiler/modules
import compiler/condsyms
import compiler/llstream
import compiler/modulegraphs
import compiler/options as compiler_options

# Script section

var identCache = newIdentCache()

type
  ScriptError* = object of Exception

proc execScript(scriptName: string): PSym =

  var message = ""
  msgs.gErrorMax = high(int)
  msgs.writeLnHook = proc(output: string) =
    if msgs.gErrorCounter > 0:
      raise newException(ScriptError, message)
    elif message.len > 0:
      echo("script: " & message)
    message = output

  try:

    initDefines()
    loadConfigs(DefaultConfig)

    defineSymbol("nimscript")

    registerPass(semPass)
    registerPass(evalPass)
    #registerPass(verbosePass)

    passes.gIncludeFile = includeModule
    passes.gImportModule = importModule

    let moduleName = scriptName.splitFile.name
    let prefixDir = splitPath(findExe("nim")).head.parentDir

    appendStr(searchPaths, prefixDir)
    appendStr(searchPaths, getAppDir())
    appendStr(searchPaths, compiler_options.libpath)

    compiler_options.gPrefixDir = prefixDir
    compiler_options.implicitIncludes.add("imports.nims")

    let graph = newModuleGraph()
    result = graph.makeModule(scriptName)

    incl(result.flags, sfMainModule)

    vm.globalCtx = newCtx(result, identCache)

    registerAdditionalOps(vm.globalCtx)
    vm.globalCtx.mode = emRepl

    template scriptRegister(name, body) {.dirty.} =
      vm.globalCtx.registerCallback moduleName & "." & astToStr(name),
        proc (a: VmArgs) =
          body

    # "Hello" function that can be called from the script
    # Also add the interface to import.nims (see file)
    scriptRegister Hello:
      echo "main: Called from main"
      a.setResult("Hello World")

    graph.compileSystemModule(identCache)
    graph.processModule(result, llStreamOpen(scriptName, fmRead), nil, identCache)

    if msgs.gErrorCounter > 0:
      raise newException(ScriptError, message)
    elif message.len > 0:
      echo("script: " & message)

  except ScriptError:
    echo getCurrentExceptionMsg()

proc cleanScript() =
  resetSystemArtifacts()
  msgs.writeLnHook = nil
  msgs.gErrorMax = 1
  vm.globalCtx = nil
  clearPasses()
  initDefines()

# Main section

if isMainModule:

  discard execScript(getAppDir() / "script.nims")
  cleanScript()
