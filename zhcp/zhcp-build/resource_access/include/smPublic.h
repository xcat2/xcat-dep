// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _SM_PUBLIC_H
#define _SM_PUBLIC_H

#include <netinet/in.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>

#define BUFLEN 256
#define MAXCACHENAMELEN 8+1+8
#define CACHEENTRYLEN BUFLEN+MAXCACHENAMELEN
#define PATHLENGTH 512
#define LENGTH_OF_USERID_LENGTH_FIELD 4
#define ALL_SCAN_FILES "*.scan"
#define PORT_FILENAME "vmbkend.UDP"

// Data structure to character based information
typedef struct _Record {
	struct _Record* nextP;
	char data[1];
} Record;

// Data structure to keep lists of records
typedef struct _List {
	Record* firstP;
	Record* currentP;
	int size;
} List;

enum Times {
	ConnectRetryLimit = 10, // # trials for connect
	SEND_RETRY_LIMIT = 8, // # times to retry send to SMAPI
	Delay = 10, // Delay in loop checking for pending workunits
	MaxWaitCycleN = 10, // Max number of wait cycles for pending ops
	SleepInterval = 15, // Interval in seconds to sleep on repetitive operations
	Socket_Timeout = 240, // Max timeout for socket operations
	Socket_Indication_Timeout = 500, // Max timeout for indication socket operations
	ImageSetRange = 4096, // # image disks in an image set
	LINESIZE = 512
// # bytes to use for a message/log line
};

// Resource layer specific function call return codes for internal/unexpected errors
// Look in the internal context for other specific return and reason codes
// listed below
//
// NOTE Parser return codes are using -4000 to -4010 see smapiTableParser.h for details.
#define MEMORY_ERROR -999
#define INVALID_DATA -2
#define PROCESSING_ERROR -3

// These are from smSocket.c functions
#define SOCKET_OBTAIN_ERROR           -100
#define SOCKET_CONNECT_REFUSED_ERROR  -101
#define SOCKET_CONNECT_TRYAGAIN_ERROR -102
#define SOCKET_TIMEOUT_ERROR          -103
#define SOCKET_READ_ERROR             -104
#define SOCKET_READ_RETRYABLE_ERROR   -105
#define SOCKET_WRITE_ERROR            -106
#define SOCKET_WRITE_RETRYABLE_ERROR  -107
#define SOCKET_PROCESSING_ERROR       -108
#define CUSTOM_DEFINED_SOCKET_RETRY   100

// Return and reason codes
enum ReturnCodes {
	RcWarning = 4, RcContext = -1, // Context related errors
	RcSession = -2, // Session related errors
	RcFunction = -3, // Errors invoking functions
	RcRuntime = -4, // General runtime errors
	RcIucv = -5, // Error caused by IUCV, reason code is IUCV return value
	RcCp = -6, // CP command invocation errors
	RcCpint = -7, // CPint invocation
	RcNoMemory = -8
// Out of memory and no context yet
};

enum GeneralReasonCodes {
	RsInternalBufferTooSmall = 10000, RsNoMemory = 10001,
	RsSemaphoreNotCreated = 10011, RsSemaphoreNotObtained = 10012,
	RsSemaphoreNotReleased = 10013, RsSocketAddrIdFileNotOpened = 10014,
	RsUnableToOpenLog = 10100, RsSocketTimeout = 10110, RsUnexpected = 10200
};

enum ContextReasonCodes {
	RsNoHostname = 1, RsNoHostId = 2, RsNoServerAssociation = 3,
	RsNoUserid = 4, RsInvalidVmapiServerVersion = 5, RsInvalidServerName = 6
};

enum SessionReasonCodes {
	RsUnableToReadSessionContext = 1, RsUnableToWriteSessionContext = 2
};

enum FunctionReasonCodes {
	RsFunctionNotSpecified = 1, RsFunctionUnknown = 2,
	RsFunctionNotImplemented = 3, RsInvalidNumberOfArguments = 4,
	RsFunctionNotSupported = 5, RsInvalidArgument = 24
};

enum RuntimeReasonCodes {
	RsUnableToOpenLog22 = 1
};

typedef struct _smMemoryGroupContext {
	int arraySize;
	int lastChunk;
	void ** chunks;
} smMemoryGroupContext;

#define CACHE_PATH_DEFAULT "/var/opt/ibm/zvmmap/.vmapi/"
#define CACHE_SEMAPHORE_DIRECTORY ".vmapi/"
#define CACHE_SEMAPHORE_FILENAME "vmapi.sem"
#define CACHE_DIRECTORY  ".cache/"
#define CACHE_DIRECTORY_FOR_USER "cache/"
#define CACHE_FILE_EXTENSION_FOR_USER ".cache"
#define CACHE_INSTANCEID_FILE_EXTENSION_FOR_USER ".id"

// A macro to free memory and zero out the pointer too
#define FREE_MEMORY(_mempointer_) \
  if (_mempointer_) \
	{                  \
	  free(_mempointer_); \
	  _mempointer_ = NULL; \
	}

#define TO_STRING2(_data_) \
     #_data_
#define TO_STRING(_data_) \
     TO_STRING2(_data_)

/**
 * Before calling the resource layer the caller needs to create and zero out
 * a VmApiInternalContext and set the following fields:
 *
 * smMemoryGroupContext structure pointed to by the memContext field. That
 * memory structure should also be zeroed out.
 *
 * --- Trace info ---
 * Set a trace flags structure pointer using the global external name:
 * extern struct _smtrace externSmapiTraceFlags;
 *
 * Ex:
 * vmapiContext.smTraceDetails = (struct _smTrace *)&externSmapiTraceFlags;
 *
 * That structure can be zero'ed out for no tracing or flags set to trace
 * a specific area. See smTraceAndError.h for constants.
 *
 * Note: The first socket init call will call readTraceFile and look for a
 * file (TRACE_LEVELS_FILE) to read and set trace levels if any are found.
 */
#define FIRST_FAILURE_MESSAGE_MAX_LEN 250
typedef struct _VmApiInternalContext {
	char serverName[256];
	int pendingWorkunits[10];
	struct _smTrace * smTraceDetails; // Trace and error flags, locations, etc
	char userid[9]; // Used for context creation default userID
	char IucvUserid[9]; // SMAPI machine UserID.  If this field is null, default is VSMREQIU
	char useridForAsynchNotification[9]; // This is usually the Linux ID, can be any ID in SMAPI auth file
	smMemoryGroupContext * memContext;
	char vmapiServerVersion[4];
	int maxServerRpcVersion;
	int contextCreatedFlag; // Set to 1 if context has been created
	char strFirstFailureMsg[FIRST_FAILURE_MESSAGE_MAX_LEN + 1];
	int firstFailureCaptured; // 0: False
	int rc;
	int reason;
	int printOffset;
	int execDepth;
	int isBackend;
	int checkBackendFlag;
	key_t semKey;
	int semId;
	FILE* logFileP;
	FILE* contextFileP;
	List inputStream;
	List outputStream;
	List errorStream;
	char path[PATHLENGTH]; // Context path in ZVMMAP_VAR or defaulted
	char name[256];
	char emsg[LINESIZE];
	char hostid[20];
	char password[9];
	int instanceId;
	char tag[256];
	int resolveHostName; // To be moved to persistant later
} VmApiInternalContext;

typedef struct _Abbreviation {
	char* nameP;
	int minimum;
} Abbreviation;

// Internal data structure to keep minidisk data
typedef struct _Minidisk {
	struct _Minidisk* nextP;
	int address;
	char type[8];
	int location;
	int extent;
	char volser[8];
	char mode[4];
	int processFlag;
} Minidisk;

// Internal data structure to keep dedicate data
typedef struct _Dedicate {
	struct _Dedicate* nextP;
	int vnum;
	int rnum;
} Dedicate;

/**
 * Macro: break_if_error(FUNC, CODE, SOCK)
 *
 * Purpose: After a socket function, this macro will display a msg using
 *          perror if the function FUNC fails with code CODE.  Additionally,
 *          if the value of the socket SOCK is not -1, the socket will be
 *          closed.  Finally, do the 'break' part, to break out of the
 *          current loop.
 *
 * Inputs:  FUNC - String to be displayed along with with perror
 *          CODE - The return code to be tested for failure (< 0)
 *          SOCK - The socket descriptor to be close if not equal to -1
 */
#ifndef break_if_error
#define break_if_error(FUNC,CODE,SOCK) { \
  if (CODE < 0) { \
    perror(#FUNC "() failed"); \
    if (SOCK != -1) { \
      close(SOCK); \
      SOCK = -1; \
    } \
    break; }}
#endif

/**
 * Macro: continue_if_error(FUNC, CODE, SOCK)
 *
 * Purpose: After a socket function, this macro will display a msg using
 *          perror if the function FUNC fails with code CODE.  Additionally,
 *          if the value of the socket SOCK is not -1, the socket will be
 *          closed.  Finally, do the 'continue' part, to iterate the
 *          current loop.
 *
 * Inputs:  FUNC - String to be displayed along with with perror
 *          CODE - The return code to be tested for failure (< 0)
 *          SOCK - The socket descriptor to be close if not equal to -1
 *
 */
#ifndef continue_if_error
#define continue_if_error(FUNC,CODE,SOCK) { \
  if (CODE < 0) { \
    perror(#FUNC "() failed"); \
    if (SOCK != -1) { \
      close(SOCK); \
      SOCK = -1; \
    } \
    continue; }}
#endif

/**
 * Macro: exit_if_error(FUNC, CODE, SOCK)
 *
 * Purpose: After a socket function, this macro will display a msg using
 *          perror if the function FUNC fails with code CODE.  Additionally,
 *          if the value of the socket SOCK is not -1, the socket will be
 *          closed.  Finally, cause the 'return' to happen.
 *
 * Inputs:  FUNC - String to be displayed along with with perror
 *          CODE - The return code to be tested for failure (< 0)
 *          SOCK - The socket descriptor to be close if not equal to -1
 */
#ifndef exit_if_error
#define exit_if_error(FUNC,CODE,SOCK) { \
  if (CODE < 0) { \
    perror(#FUNC "() failed"); \
    if (SOCK != -1) { \
      close(SOCK); \
      SOCK = -1; \
    } \
    return; }}
#endif

// Macros to retrieve or default argument
#define ARG(x) getArg(x,anArgc,anArgvPP,"")
#define ARG_DEFAULT(x,aDefaultP) getArg(x,anArgc,anArgvPP,aDefaultP)

// Utility functions
int checkAbbreviation(const char* aStringP,
		const Abbreviation* anAbbreviationListP, int anAbbreviationN);

int checkBoolean(const char* aStringP);

int checkPrefixCommand(const char* aCommandP);

int initializeThreadSemaphores(struct _VmApiInternalContext* vmapiContextP,
		const char* aContextNameP, int aCreateFlag);

int createDirectories(const char* aFilenameP);

void dumpArea(struct _VmApiInternalContext* vmapiContextP, void * pstor,
		int len);

Dedicate* getDedicates();
Minidisk* getMinidisks();

int isOSA(struct _VmApiInternalContext* vmapiContextP, char* rdev);

void listAppendLine(struct _VmApiInternalContext* vmapiContextP, List* aListP,
		const char* aLineP);

void listAppendRecord(List* aListP, Record* aRecordP);

void listDeleteCurrent(List* aListP);

Record*
listDequeueRecord(List* aListP);

const char*
listNextLine(List* aListP);

const Record*
listNextRecord(List* aListP);

void listFree(List* aListP);

void listReset(List* aListP);

void readTraceFile(struct _VmApiInternalContext* vmapiContextP);

void *
smMemoryGroupAlloc(struct _VmApiInternalContext* vmapiContextP, size_t size);

int smMemoryGroupFreeAll(struct _VmApiInternalContext* vmapiContextP);

int smMemoryGroupInitialize(struct _VmApiInternalContext* vmapiContextP);

void *
smMemoryGroupRealloc(struct _VmApiInternalContext* vmapiContextP, void * chunk,
		size_t size);

int smMemoryGroupTerminate(struct _VmApiInternalContext* vmapiContextP);

char*
strip(char* aLineP, char anOption, char aChar);

void sysinfo(struct _VmApiInternalContext* vmapiContextP, int anArgc,
		const char**anArgvPP);

int testDigit(char aChar);

const char*
vmApiMessageText(struct _VmApiInternalContext* vmapiContextP);

int vmbkendCacheEntryInvalidate(struct _VmApiInternalContext* vmapiContextP,
		char *pathP, char *useridP);

int vmbkendCheck(struct _VmApiInternalContext* vmapiContextP);

void vmbkendGetCachePath(struct _VmApiInternalContext* vmapiContextP,
		char *pathP);

void *vmbkendMain(void* vmapiContextP);

int vmbkendRemoveCachedScanFiles(struct _VmApiInternalContext* vmapiContextP,
		char *pathP);

void vmbkendRemoveEntireCache(struct _VmApiInternalContext* vmapiContextP,
		char *cachePathP);

void waitForPendingWorkunits(struct _VmApiInternalContext* vmapiContextP,
		int waitIntervalInSeconds);

int cacheFileValid(struct _VmApiInternalContext* vmapiContextP,
		const char* cFName);

#include "smTraceAndError.h"

#endif
