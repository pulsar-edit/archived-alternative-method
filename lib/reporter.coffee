_ = require 'underscore-plus'
os = require 'os'
request = require 'request'
stackTrace = require 'stack-trace'
API_KEY = '7ddca14cb60cbd1cd12d1b252473b076'

StackTraceCache = new WeakMap

buildNotificationJSON = (error, params) ->
  apiKey: API_KEY
  notifier:
    name: 'Atom'
    version: params.appVersion
    url: 'https://www.atom.io'
  events: [{
    payloadVersion: "2"
    exceptions: [buildExceptionJSON(error, params.projectRoot)]
    severity: params.severity
    user:
      id: params.userId
    app:
      version: params.appVersion
      releaseStage: params.releaseStage
    device:
      osVersion: params.osVersion
    metaData: error.metadata
  }]

buildExceptionJSON = (error, projectRoot) ->
  errorClass: error.constructor.name
  message: error.message
  stacktrace: buildStackTraceJSON(error, projectRoot)

buildStackTraceJSON = (error, projectRoot) ->
  projectRootRegex = ///^#{_.escapeRegExp(projectRoot)}[\/\\]///i
  parseStackTrace(error).map (callSite) ->
    file: callSite.getFileName().replace(projectRootRegex, '')
    method: callSite.getMethodName() ? callSite.getFunctionName() ? "none"
    lineNumber: callSite.getLineNumber()
    columnNumber: callSite.getColumnNumber()
    inProject: not /node_modules/.test(callSite.getFileName())

getDefaultNotificationParams = ->
  userId: atom.config.get('exception-reporting.userId')
  appVersion: atom.getVersion()
  releaseStage: if atom.isReleasedVersion() then 'production' else 'development'
  projectRoot: atom.getLoadSettings().resourcePath
  osVersion: "#{os.platform()}-#{os.arch()}-#{os.release()}"

performRequest = (json) ->
  options =
    method: 'POST'
    url: 'https://notify.bugsnag.com'
    headers: 'Content-Type': 'application/json'
    body: JSON.stringify(json)
  request options, -> # Empty callback prevents errors from going to the console

shouldReport = (error) ->
  return true if exports.alwaysReport # Used in specs
  return false if atom.inDevMode()

  if topFrame = parseStackTrace(error)[0]
    # only report exceptions that originate from the application bundle
    topFrame.getFileName().indexOf(atom.getLoadSettings().resourcePath) is 0
  else
    false

parseStackTrace = (error) ->
  if callSites = StackTraceCache.get(error)
    callSites
  else
    callSites = stackTrace.parse(error)
    StackTraceCache.set(error, callSites)
    callSites

exports.reportUncaughtException = (error) ->
  return unless shouldReport(error)

  params = getDefaultNotificationParams()
  params.severity = "error"
  json = buildNotificationJSON(error, params)
  performRequest(json)

exports.reportFailedAssertion = (error) ->
  return unless shouldReport(error)

  params = getDefaultNotificationParams()
  params.severity = "warning"
  json = buildNotificationJSON(error, params)
  performRequest(json)

# Used in specs
exports.setRequestFunction = (requestFunction) ->
  request = requestFunction

exports.API_KEY = API_KEY