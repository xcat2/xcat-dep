// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _SM_TRACE_H
#define _SM_TRACE_H
#include <stdio.h>
#include <syslog.h>
#include "smPublic.h"

// Trace levels are to be powers of 2 to allow combinations of tracing
#define TRACE_LEVELS_FILE "vmmaptracing"
#define TRACE_LEVELS_FILE_DIRECTORY "/etc/opt/ibm/zvmmap/.cimvm/"

// Make sure the level information matches the index in the TRACE_LEVELS and TRACE_FLAG_VALUES array below
#define TRACELEVEL_OFF        0
#define TRACELEVEL_FLOW       1
#define TRACELEVEL_PARAMETERS 2
#define TRACELEVEL_DETAILS    4
#define TRACELEVEL_BUFFER_OUT    256  // Unit test socket layer
#define TRACELEVEL_BUFFER_IN     512  // Unit test socket layer
#define TRACELEVEL_ALL        0x8FFFFFFF

// Keywords for the trace file
#define TRACE_LEVELS_COUNT    7
static const char * TRACE_LEVELS[TRACE_LEVELS_COUNT] = { "off", "flow",
		"parms", "details", "buffout", "buffin", "all" };

static const unsigned int TRACE_FLAG_VALUES[TRACE_LEVELS_COUNT] = { 0,
		TRACELEVEL_FLOW, TRACELEVEL_PARAMETERS, TRACELEVEL_DETAILS,
		TRACELEVEL_BUFFER_OUT, TRACELEVEL_BUFFER_IN, TRACELEVEL_ALL };

// Trace areas index into trace array
#define TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD 0
#define TRACEAREA_CIM_OPERATION_LAYER 1
#define TRACEAREA_RESOURCE_LAYER      2
#define TRACEAREA_RESOURCE_LAYER_SOCKET 3
#define TRACEAREA_RESOURCE_LAYER_PARSER 4
#define TRACEAREA_BACKGROUND_VMEVENT_NOTIFICATION_THREAD 5
#define TRACEAREA_NAME_VALUE_PARSER 6
#define TRACEAREA_CACHE 7
#define TRACEAREA_SMAPI_ONLY 8

// Keywords for the trace areas
#define TRACE_AREAS_COUNT  9
static const char * TRACE_KEYWORDS[TRACE_AREAS_COUNT] = { "directorychanges",
		"cimop", "resourcelayer", "socket", "parser", "vmeventchanges",
		"namevalueparser", "cache", "smapionly" };

typedef struct _smTrace {
	unsigned int traceFlags[TRACE_AREAS_COUNT]; // A separate trace int for each area
	int traceLock;
	int traceFileRead; // 0 = trace file needs to be checked with "readTraceFile("
	unsigned int traceOutputLocation; // 0 = syslog
	FILE * traceFilePointer; // 0 = no file open
} smTrace;

/**
 * Trace functions and constants for a line of data or a block of storage
 */

// errorLog will save the return and reason code in the context and then
// call errorLine.
void errorLog(struct _VmApiInternalContext* vmapiContextP,
		const char * functionName, const char * lineNumber, int aRc,
		int aReason, const char* aLineP);

// errorLine will call Logline with the "error" flag and then
// call listAppendLine to add a record to the context error stream
void errorLine(struct _VmApiInternalContext* vmapiContextP, const char* aLineP);

// These severity contants get remapped to syslog constants in LogLine
#define LOGLINE_DEBUG     'D'
#define LOGLINE_ERR       'E'
#define LOGLINE_INFO      'I'
#define LOGLINE_NOTICE    'N'
#define LOGLINE_WARNING   'W'
#define LOGLINE_EXCEPTION 'X'

// LogLine will add a timestamp and then write the data to the syslog.
void logLine(struct _VmApiInternalContext* vmapiContextP, char aSeverity,
		const char* aLineP);

void outputLine(struct _VmApiInternalContext* vmapiContextP,
		const char* aLineP, int aLogFlag);

// This macro can be used to test for a trace type being on before
// calling logLine. See logline description below. Follow the logLine
// call with the TRACE_END or TRACE_END_DEBUG to close out the braces
// logline with the LOGLINE_DEBUG will replace the old codes use of debugline.
#define TRACE_START(_context_ , _tracearea_, _tracelevel_) \
  if(((_context_)->smTraceDetails->traceFlags[_tracearea_])&_tracelevel_ ) \
  {

#define TRACE_END }

#define TRACE_END_DEBUG(_context_, _linedata_) \
	logLine(_context_, LOGLINE_DEBUG,  _linedata_); \
	}

// This macro can be used to trace entry into a function,
// the function name is supplied by the compiler
#define TRACE_ENTRY_FLOW(_context_ , _tracearea_) \
 TRACE_START(_context_, _tracearea_, TRACELEVEL_FLOW); \
		char _line_[LINESIZE]; \
		sprintf(_line_,  \
							"%s function ENTRY                (at line %d in %s) \n",   \
							__func__, __LINE__, __FILE__);  \
		logLine(_context_ ,LOGLINE_DEBUG, _line_);  \
 }

// This macro can be used to trace exit from a function,
// the function name is supplied by the compiler
// The context is expected to be a pointer
#define TRACE_EXIT_FLOW(_context_ , _tracearea_) \
 TRACE_START(_context_, _tracearea_, TRACELEVEL_FLOW); \
		char _line_[LINESIZE]; \
		sprintf(_line_,  \
						"%s function EXIT. RC: %d RS: %d                (at line %d in %s) \n",   \
						__func__, \
						_context_->rc, \
						_context_->reason, __LINE__, __FILE__);  \
		logLine(_context_ ,LOGLINE_DEBUG, _line_);  \
 }

// This macro can be used to trace exit from a CIM function where you specify the return code,
// the function name is supplied by the compiler
// The context is expected to be a pointer
#define TRACE_EXIT_CIM_FLOW(_context_ , _tracearea_ , _rc_) \
 TRACE_START(_context_, _tracearea_, TRACELEVEL_FLOW); \
		char _line_[LINESIZE]; \
		sprintf(_line_,  \
						"%s function EXIT. RC: %d              (at line %d in %s) \n",   \
						__func__, \
						_rc_, __LINE__, __FILE__); \
		logLine(_context_ ,LOGLINE_DEBUG, _line_);  \
 }

#endif
