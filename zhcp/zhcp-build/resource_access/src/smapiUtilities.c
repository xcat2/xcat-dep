// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "smPublic.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <netinet/in.h>
#include <sys/stat.h>
#include <sys/sem.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <pthread.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <dlfcn.h>
#include <ctype.h>
#include <rpc/rpc.h>
#include <arpa/inet.h>

#include "vmapiSystem.h"
#include "vmapiAsynchronous.h"
#include "vmapiQuery.h"
#include "smapiTableParser.h"
#include "smSocket.h"

#define VMAPILIB "libvmapi.so"

int vmbkendSockaddrFileInfo(struct _VmApiInternalContext* vmapiContextP,
		int readOrWrite, struct sockaddr_in *saddr);

// Externally visible storage for trace
smTrace externSmapiTraceFlags = { 0 };

// Semaphore locking fields for trace and the backend
enum SemaphoreIndex {
	ContextSemaphoreIndex = 0, TraceSemaphoreIndex = 1,
	BackendSemaphoreIndex = 2, NumberOfSemaphores
};

// ------------ Context ones ------------
static struct sembuf contextSemaphoreReserve[] = { ContextSemaphoreIndex, -1,
		SEM_UNDO };
static const int contextSemaphoreReserveN = sizeof(contextSemaphoreReserve)
		/ sizeof(contextSemaphoreReserve[0]);

static struct sembuf contextSemaphoreRelease[] = { ContextSemaphoreIndex, 1,
		SEM_UNDO };
static const int contextSemaphoreReleaseN = sizeof(contextSemaphoreRelease)
		/ sizeof(contextSemaphoreRelease[0]);

// ------------ Trace ones ------------
static struct sembuf traceSemaphoreReserve[] = { TraceSemaphoreIndex, -1,
		SEM_UNDO };
static const int traceSemaphoreReserveN = sizeof(traceSemaphoreReserve)
		/ sizeof(traceSemaphoreReserve[0]);

static struct sembuf traceSemaphoreRelease[] = { TraceSemaphoreIndex, 1,
		SEM_UNDO };
static const int traceSemaphoreReleaseN = sizeof(traceSemaphoreRelease)
		/ sizeof(traceSemaphoreRelease[0]);

// ------------ VMbackend ones ------------
static struct sembuf backendSemaphoreReserve[] = { BackendSemaphoreIndex, -1,
		SEM_UNDO };
static const int backendSemaphoreReserveN = sizeof(backendSemaphoreReserve)
		/ sizeof(backendSemaphoreReserve[0]);

static struct sembuf backendSemaphoreRelease[] = { BackendSemaphoreIndex, 1,
		SEM_UNDO };
static const int backendSemaphoreReleaseN = sizeof(backendSemaphoreRelease)
		/ sizeof(backendSemaphoreRelease[0]);

pthread_mutex_t mutex;
pthread_cond_t thread_initialized_cv;

int checkAbbreviation(const char* aStringP,
		const Abbreviation* anAbbreviationListP, int anAbbreviationN) {

	int x;
	int checkL;
	int stringL;

	int isAbbreviation = 0;
	if (aStringP == 0)
		return 0;

	stringL = strlen(aStringP);

	for (x = 0; x < anAbbreviationN; ++x) {
		checkL = anAbbreviationListP[x].minimum;
		if (checkL > stringL)
			continue;
		if (0 == strncasecmp(aStringP, anAbbreviationListP[x].nameP, checkL)) {
			isAbbreviation = 1;
			break;
		}
	}

	return isAbbreviation;

}

int checkBoolean(const char* aStringP) {

	const Abbreviation booleanTrues[] = { { "TRUE", 1 }, { "YES", 1 },
			{ "1", 1 } };

	return checkAbbreviation(aStringP, booleanTrues, (sizeof(booleanTrues)
			/ sizeof(booleanTrues[0])));

}

int checkPrefixCommand(const char* aCommandP) {

	const Abbreviation prefixCommands[] = { { "REQUEST", 3 }, { "TOSYS", 5 }, {
			"TONODE", 6 }, { "ASUSER", 2 }, { "BYUSER", 2 }, { "FORUSER", 3 },
			{ "PRESET", 6 }, { "MULTIUSER", 5 }, { "ATNODE", 6 },
			{ "ATSYS", 5 } };

	return checkAbbreviation(aCommandP, prefixCommands, (sizeof(prefixCommands)
			/ sizeof(prefixCommands[0])));

}

const char*
contextGetMessageFilename(struct _VmApiInternalContext* vmapiContextP,
		char* aBufferP, int aBufferS) {

	char line[LINESIZE];
	int len = 0;
	const char* msgName = "messages";
	const char* msgSuffixName = ".eng"; // Language-dependent
	char* pathP = 0;
	int pathL = 0;

	TRACE_ENTRY_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);

	// Obtain VMAPI environment variable
	memset(aBufferP, 0, aBufferS);
	pathP = getenv("VMAPI");

	if (pathP) {
		pathL = strlen(pathP);
		len = pathL + 12; // Adjust once we know NLS file structure
		if (len > aBufferS) {
			sprintf(
					line,
					"contextGetMessageFilename: Insufficient path buffer size; needed %d, have %d.",
					len, (aBufferS - 1));
			errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcContext,
					RsInternalBufferTooSmall, line);
		}
		strncpy(aBufferP, pathP, pathL);
		if (aBufferP[pathL - 1] == '/') {
			strcat(aBufferP, ".cimvm/");
		} else {
			strcat(aBufferP, "/.cimvm/");
		}
	} else {
		strcpy(aBufferP, "/root/.cimvm/");
	}

	strcat(aBufferP, msgName); // Adjust when we know real NLS stuff
	strcat(aBufferP, msgSuffixName);

	return aBufferP;

}

int createDirectories(const char* aFilenameP) {

	int filenameL = strlen(aFilenameP);
	char filename[LINESIZE];
	int rc;
	char* sP = 0;
	char* eP = 0;

	if (filenameL >= (sizeof(filename) - 1))
		return 0;

	memset(filename, 0, sizeof(filename));
	strcpy(filename, aFilenameP);

	sP = filename;
	eP = filename + sizeof(filename) - 1;
	while ((sP < eP) && (sP = strchr(sP + 1, '/'))) {
		*sP = '\0';
		mkdir(filename, S_IRWXU);
		*sP = '/';
	}

	return 0;

}

int initializeThreadSemaphores(struct _VmApiInternalContext* vmapiContextP,
		const char* aContextNameP, int aCreateFlag) {
	char pathAndFile[PATHLENGTH + strlen(CACHE_SEMAPHORE_FILENAME)];
	FILE* idFileP = 0;
	int len = 0;
	char line[LINESIZE];
	const char* logFilenameP = 0;
	union semun {
		int val;
		struct semid_ds* buf;
		ushort* array;
	} semArgument;
	int semInitRequired = 0;
	int pathLength = 0;
	char* pathPtr = 0;
	int rc = 0;
	int savedSize = 0;

	memset(vmapiContextP->path, 0, sizeof(vmapiContextP->path)); // Clear out path string
	memset(pathAndFile, 0, sizeof(pathAndFile));

	// Save the name passed in; into the context if specified
	if (strlen(aContextNameP) > 0) {
		strncpy(vmapiContextP->name, aContextNameP, sizeof(vmapiContextP->name)
				- 1);
	}

	// Obtain VMAPI environment variable
	pathPtr = getenv("ZVMMAP_VAR");
	if (pathPtr) { // ZVMMAP_VAR is defined
		pathLength = strlen(pathPtr);
		len = pathLength + strlen(CACHE_SEMAPHORE_DIRECTORY);
		if (len > sizeof(pathAndFile)) {
			sprintf(
					line,
					"contextReserve: Insufficient path buffer size; needed %d, have %d.",
					len, sizeof(pathAndFile) - 1);
			errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcContext,
					RsInternalBufferTooSmall, line);
			return PROCESSING_ERROR;
		}
		strncpy(vmapiContextP->path, pathPtr, sizeof(vmapiContextP->path)
				- (strlen(CACHE_SEMAPHORE_DIRECTORY) + 2));
		len = strlen(vmapiContextP->path);
		if (vmapiContextP->path[len - 1] == '/') {
			strcat(vmapiContextP->path, CACHE_SEMAPHORE_DIRECTORY); // Add on .vmapi/ directory
		} else {
			strcat(vmapiContextP->path, "/");
			strcat(vmapiContextP->path, CACHE_SEMAPHORE_DIRECTORY);
		}
	} else { // ZVMMAP_VAR is undefined, set default
		strcpy(vmapiContextP->path, CACHE_PATH_DEFAULT);
	}

	// Create or obtain semaphore set
	strcpy(pathAndFile, vmapiContextP->path);
	strcat(pathAndFile, CACHE_SEMAPHORE_FILENAME);
	createDirectories(pathAndFile);

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_SOCKET,
			TRACELEVEL_DETAILS);
	sprintf(line, "initializeThreadSemaphores: Semaphore file name is   %s \n",
			pathAndFile);
	TRACE_END_DEBUG(vmapiContextP, line);

	// Try to open or create a file that can be used for semaphore handle
	FILE* semFileP = fopen(pathAndFile, "r");
	if (!semFileP) {
		semFileP = fopen(pathAndFile, "w");
	}
	if (semFileP) {
		fclose(semFileP);
	}

	vmapiContextP->semKey = ftok(pathAndFile, 'V');
	vmapiContextP->semId = semget(vmapiContextP->semKey, 2, 0600);

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_SOCKET,
			TRACELEVEL_DETAILS);
	sprintf(line, "initializeThreadSemaphores: semKey = %d \n",
			vmapiContextP->semKey);
	TRACE_END_DEBUG(vmapiContextP, line);

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_SOCKET,
			TRACELEVEL_DETAILS);
	sprintf(line, "initializeThreadSemaphores: semId = %d \n",
			vmapiContextP->semId);
	TRACE_END_DEBUG(vmapiContextP, line);

	if ((0 > vmapiContextP->semId) && (ENOENT == errno)) {
		semInitRequired = 1;
		vmapiContextP->semId = semget(vmapiContextP->semKey,
				NumberOfSemaphores, 0600 | IPC_CREAT);
	}

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_SOCKET,
			TRACELEVEL_DETAILS);
	sprintf(line, "initializeThreadSemaphores: semInitRequired = %d \n",
			semInitRequired);
	TRACE_END_DEBUG(vmapiContextP, line);

	if (0 > vmapiContextP->semId) {
		sprintf(
				line,
				"contextReserve: Unable to create semaphore array identified by %s; errno=%d text: %s",
				pathAndFile, errno, strerror(errno));
		errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
				RsSemaphoreNotCreated, line);
		return PROCESSING_ERROR;
	}

	if (semInitRequired) {
		semArgument.val = 1;
		rc = semctl(vmapiContextP->semId, TraceSemaphoreIndex, SETVAL,
				semArgument);
		if (0 > rc) {
			sprintf(line,
					"Unable to initialize Trace semaphore; errno=%d text: %s",
					errno, strerror(errno));
			errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
					RsSemaphoreNotCreated, line);
			return PROCESSING_ERROR;
		}

		rc = semctl(vmapiContextP->semId, BackendSemaphoreIndex, SETVAL,
				semArgument);
		if (0 > rc) {
			sprintf(
					line,
					"Unable to initialize Backend semaphore; errno=%d text: %s",
					errno, strerror(errno));
			errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
					RsSemaphoreNotCreated, line);
			return PROCESSING_ERROR;
		}
		rc = semctl(vmapiContextP->semId, ContextSemaphoreIndex, SETVAL,
				semArgument);
		if (0 > rc) {
			sprintf(
					line,
					"Unable to initialize context semaphore; errno=%d text: %s",
					errno, strerror(errno));
			errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
					RsSemaphoreNotCreated, line);
			return PROCESSING_ERROR;
		}
	}

	// Obtain the Context  semaphore before manipulating context related stuff
	rc = semop(vmapiContextP->semId, contextSemaphoreReserve,
			contextSemaphoreReserveN);
	if (rc < 0) {
		sprintf(line,
				"contextReserve: semop (decrement) failed; errno=%d text: %s",
				errno, strerror(errno));
		errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
				RsSemaphoreNotObtained, line);
		return PROCESSING_ERROR;
	}

	// Create or obtain context for the name passed in
	strcpy(pathAndFile, vmapiContextP->path);
	strcat(pathAndFile, CACHE_DIRECTORY);
	createDirectories(pathAndFile);

	// Release the Context semaphore after manipulating context related stuff
	rc = semop(vmapiContextP->semId, contextSemaphoreRelease,
			contextSemaphoreReleaseN);
	if (rc < 0) {
		sprintf(line,
				"contextReserve: semop (increment) failed, errno=%d text: %s",
				errno, strerror(errno));
		errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
				RsSemaphoreNotReleased, line);
		return PROCESSING_ERROR;
	}
	vmapiContextP->contextCreatedFlag = 1; // Set flag to indicate context set up
	return 0;
}

/**
 * Unit test code
 */
void dumpArea(struct _VmApiInternalContext* vmapiContextP, void * pstor,
		int len) {
	unsigned int offset, i, j, k;
	char trans[17];
	char line[LINESIZE];
	char phrase[80];
	unsigned char storByte;
	int transAvail;
	offset = 0;
	transAvail = 0;
	for (k = 0; k < sizeof(trans); k++) {
		trans[k] = '\0';
	}

	storByte = *((char *) pstor);
	sprintf(line, "=== dump of area %p for length %d ", pstor, len);
	for (i = 0; i < len; i++) {
		j = i % 16;
		if (j == 0) {
			if (transAvail) {
				sprintf(phrase, " %s", trans);
				strcat(line, phrase);
				for (k = 0; k < sizeof(trans); k++) {
					trans[k] = '\0';
				}
				transAvail = 0;
			}
			strcat(line, "\n");
			logLine(vmapiContextP, LOGLINE_DEBUG, line);
			sprintf(line, "%6d %14p   ", offset, (pstor + offset));
			offset += 16;
		} else if (0 == (k = i % 4)) {
			strcat(line, " ");
		}
		storByte = *((char*) (pstor + i));
		if (isprint(storByte)) {
			trans[j] = storByte;
		} else {
			trans[j] = '.';
		}
		transAvail = 1;

		sprintf(phrase, "%02X", storByte);
		strcat(line, phrase);

	}
	if (transAvail) {
		for (k = j + 1; k < 16; k++) {
			if (0 == k % 4) {
				strcat(line, " ");
			}
			strcat(line, "  ");
		}
		sprintf(phrase, " %s", trans);
		strcat(line, phrase);
	}
	strcat(line, "\n");
	logLine(vmapiContextP, LOGLINE_DEBUG, line);
}

void errorLog(struct _VmApiInternalContext* vmapiContextP,
		const char * functionName, const char * lineNumber, int aRc,
		int aReason, const char* aLineP) {

	char line[LINESIZE];

	sprintf(line, "%s:%s %s", functionName, lineNumber, aLineP);

	vmapiContextP->rc = aRc;
	vmapiContextP->reason = aReason;
	errorLine(vmapiContextP, line);

}

void errorLine(struct _VmApiInternalContext* vmapiContextP, const char* aLineP) {
	int lineL = strlen(aLineP);

	logLine(vmapiContextP, 'E', aLineP);

	// If this is the first error for this context, save it
	if (!vmapiContextP->firstFailureCaptured) {
		strncpy(vmapiContextP->strFirstFailureMsg, aLineP,
				FIRST_FAILURE_MESSAGE_MAX_LEN);
		vmapiContextP->strFirstFailureMsg[FIRST_FAILURE_MESSAGE_MAX_LEN] = '\0';
		vmapiContextP->firstFailureCaptured = 1; // 1:true
	}

}

char*
getArg(int anIndex, int anArgc, const char** anArgvPP, const char* aDefaultP) {

	int x = anIndex;

	if (x > (anArgc - 1))
		return (char*) aDefaultP;

	return (char*) (anArgvPP[x] ? anArgvPP[x] : aDefaultP);

}

Dedicate*
getDedicates(struct _VmApiInternalContext* vmapiContextP) {

	char* itemP = 0;
	Record* recordP = 0;

	char* lastP = 0;
	char line[LINESIZE];
	char tokenLine[LINESIZE];

	Dedicate* currentDedicateP = 0;
	Dedicate* dedicatesP = 0;
	Dedicate* newDedicateP = 0;

	recordP = vmapiContextP->outputStream.currentP;

	while (recordP) {

		strncpy(tokenLine, recordP->data, sizeof(tokenLine));

		itemP = strtok_r(tokenLine, " ", &lastP);

		if (itemP && (0 == strcmp(itemP, "DEDICATE"))) {

			newDedicateP = calloc(1, sizeof(Dedicate));
			if (newDedicateP == 0) {
				while (dedicatesP != 0) {
					currentDedicateP = dedicatesP->nextP;
					free(dedicatesP);
					dedicatesP = currentDedicateP;
				}
				sprintf(line, "%s: Insufficiant memory (request=%d bytes)",
						"getDedicates", sizeof(Dedicate));
				errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
						RcRuntime, RsNoMemory, line);
				return 0;
			}

			if (currentDedicateP == 0) {
				dedicatesP = newDedicateP;
				currentDedicateP = newDedicateP;
			} else {
				currentDedicateP->nextP = newDedicateP;
				currentDedicateP = newDedicateP;
			}
			newDedicateP->nextP = 0;

			itemP = strtok_r(0, " ", &lastP);
			if (itemP) {
				sscanf(itemP, "%x", &(newDedicateP->vnum));
				itemP = strtok_r(0, " ", &lastP);
			}

			if (itemP) {
				sscanf(itemP, "%x", &(newDedicateP->rnum));
				itemP = strtok_r(0, " ", &lastP);
			}

		}

		recordP = recordP->nextP;

	}

	return dedicatesP;

}

Minidisk*
getMinidisks(struct _VmApiInternalContext* vmapiContextP) {

	char* itemP;
	Record* recordP = 0;

	char* lastP = 0;
	char line[LINESIZE];
	char tokenLine[LINESIZE];

	Minidisk* currentMinidiskP = 0;
	Minidisk* minidisksP = 0;
	Minidisk* newMinidiskP = 0;

	recordP = vmapiContextP->outputStream.firstP;

	while (recordP) {

		strncpy(tokenLine, recordP->data, sizeof(tokenLine));
		itemP = strtok_r(tokenLine, " ", &lastP);

		if (itemP && (0 == strcmp(itemP, "MDISK"))) {

			newMinidiskP = calloc(1, sizeof(Minidisk));
			if (newMinidiskP == 0) {
				while (minidisksP != 0) {
					currentMinidiskP = minidisksP->nextP;
					free(minidisksP);
					minidisksP = currentMinidiskP;
				}
				sprintf(line, "%s: Insufficiant memory (request=%d bytes)",
						"getMinidisks", sizeof(Minidisk));
				errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
						RcRuntime, RsNoMemory, line);
				return 0;
			}

			if (currentMinidiskP == 0) {
				minidisksP = newMinidiskP;
				currentMinidiskP = newMinidiskP;
			} else {
				currentMinidiskP->nextP = newMinidiskP;
				currentMinidiskP = newMinidiskP;
			}

			newMinidiskP->nextP = 0;
			itemP = strtok_r(0, " ", &lastP);
			if (itemP) {
				sscanf(itemP, "%x", &(newMinidiskP->address));
				itemP = strtok_r(0, " ", &lastP);
			}
			if (itemP) {
				strncpy(newMinidiskP->type, itemP, sizeof(newMinidiskP->type));
				itemP = strtok_r(0, " ", &lastP);
			}
			if (itemP) {
				sscanf(itemP, "%d", &newMinidiskP->location);
				itemP = strtok_r(0, " ", &lastP);
			}
			if (itemP) {
				sscanf(itemP, "%d", &newMinidiskP->extent);
				itemP = strtok_r(0, " ", &lastP);
			}
			if (itemP) {
				strncpy(newMinidiskP->volser, itemP,
						sizeof(newMinidiskP->volser));
				itemP = strtok_r(0, " ", &lastP);
			}
			if (itemP) {
				strncpy(newMinidiskP->mode, itemP, sizeof(newMinidiskP->mode));
			}

		}

		recordP = recordP->nextP;

	}

	return minidisksP;

}

/**
 * Return 	1 	If a real device number is of an OSA type
 * 			0 	Otherwise (or on failure to check)
 */
int isOSA(struct _VmApiInternalContext* vmapiContextP, char* rdev) {
	smMemoryGroupContext localMemoryGroup;
	smMemoryGroupContext * saveMemoryGroup;
	vmApiSystemIoQueryOutput * ptrCommandOutput;
	char *tokptr;
	char *delim = " ";
	char *tok;
	int osaFound = 0;
	int x;

	TRACE_ENTRY_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);

	saveMemoryGroup = vmapiContextP->memContext;
	vmapiContextP->memContext = &localMemoryGroup;

	smMemoryGroupInitialize(vmapiContextP);

	if (smSystem_IO_Query(vmapiContextP, rdev, &ptrCommandOutput)) {
		smMemoryGroupFreeAll(vmapiContextP);
		smMemoryGroupTerminate(vmapiContextP);
		vmapiContextP->memContext = saveMemoryGroup;
		return osaFound;
	}

	// Loop through all the output found looking for "OSA", "OSD", or "IQDC"
	// Output string will be "chpid string" or just "chpid"
	for (x = 0; x < ptrCommandOutput->chipidCount; x++) {
		// Get the chipid id first
		tok = strtok_r(ptrCommandOutput->chipidList->vmapiString, delim,
				&tokptr);
		// See if there is data for this chipid
		if (tok = strtok_r(NULL, delim, &tokptr)) {
			if (!strcmp(tok, "OSA") || !strcmp(tok, "OSD") || !strcmp(tok,
					"IQDC")) {
				osaFound = 1;
			}
		}
	}

	smMemoryGroupFreeAll(vmapiContextP);
	smMemoryGroupTerminate(vmapiContextP);
	vmapiContextP->memContext = saveMemoryGroup;

	return osaFound;

}

/**
 * Append data to a list
 */
void listAppendLine(struct _VmApiInternalContext* vmapiContextP, List* aListP,
		const char* aLineP) {

	int lineL = strlen(aLineP);

	Record* newRecordP = smMemoryGroupAlloc(vmapiContextP, sizeof(Record)
			+ lineL + 1);
	if (newRecordP == 0)
		return;

	strncpy(newRecordP->data, aLineP, lineL);

	listAppendRecord(aListP, newRecordP);

}

/**
 * Append data to a list
 */
void listAppendRecord(List* aListP, Record* aRecordP) {

	if (aListP->firstP == 0) {
		aListP->firstP = aRecordP;
	} else {
		if (aListP->currentP == 0) {
			aListP->currentP = aListP->firstP;
			while (aListP->currentP->nextP) {
				aListP->currentP = aListP->currentP->nextP;
			}
		}
		aListP->currentP->nextP = aRecordP;
	}
	aListP->currentP = aRecordP;
	++(aListP->size);
	aRecordP->nextP = 0;

}

/**
 * Delete the current record from the list
 */
void listDeleteCurrent(List* aListP) {

	Record* currentP = 0;
	Record* prevP = 0;

	if (aListP == 0)
		return;

	if (aListP->firstP == 0)
		return;

	// Current not set yet ?
	if (aListP->currentP == 0)
		return;

	currentP = aListP->currentP;
	if (aListP->firstP == aListP->currentP) {
		aListP->currentP = aListP->firstP->nextP;
		aListP->firstP = aListP->firstP->nextP;
	} else {
		// Find the record before aListP->currentP
		prevP = aListP->firstP;
		while (prevP && (prevP->nextP != currentP)) {
			prevP = prevP->nextP;
		}
		// Remove recordP from list
		if (prevP) {
			prevP->nextP = currentP->nextP;
		}
	}

	free(currentP);
	--(aListP->size);

}

/**
 * Dequeue a line from the front of the list
 */
Record*
listDequeueRecord(List* aListP) {

	Record* recordP = 0;

	if (aListP == 0)
		return 0;

	if (aListP->firstP == 0)
		return 0;

	recordP = aListP->firstP;

	if (recordP == aListP->currentP) {
		aListP->currentP = recordP->nextP;
	}

	aListP->firstP = recordP->nextP;

	--(aListP->size);

	return recordP;

}

/**
 * Free all records from a list
 */
void listFree(List* aListP) {

	Record* recordP = aListP->firstP;
	Record* nextP = 0;

	while (recordP) {
		nextP = recordP->nextP;
		free(recordP);
		recordP = nextP;
	}

	aListP->firstP = 0;
	aListP->currentP = 0;
	aListP->size = 0;

}

/**
 * Return Append data to a list
 */
const char*
listNextLine(List* aListP) {

	const Record* recordP = listNextRecord(aListP);
	if (recordP == 0)
		return 0;
	return recordP->data;

}

/**
 * Return Append data to a list
 */
const Record*
listNextRecord(List* aListP) {

	if (aListP == 0)
		return 0;

	if (aListP->currentP == 0) {
		// This causes a wrap around after the 0 record was returned once,
		// that is, after "end of list" was returned once.
		aListP->currentP = aListP->firstP;
	} else {
		aListP->currentP = aListP->currentP->nextP;
	}

	return aListP->currentP;

}

/**
 * Free all records from a list
 */
void listReset(List* aListP) {

	if (aListP == 0)
		return;

	aListP->currentP = 0;

}

void logLine(struct _VmApiInternalContext* vmapiContextP, char aSeverity,
		const char* aLineP) {

	int blankN = 0;
	const char* blanks = "          ";
	char line[LINESIZE];
	const char* prefix = "+         ";
	int prefixL = 0;
	int syslogSeverity = LOG_INFO;
	struct tm *tP;
	struct tm tm;
	time_t timeValue;
	pid_t pidTrace;
	pthread_t myThread;
	int temp;

	pidTrace = getpid();
	myThread = pthread_self();

	switch (aSeverity) {
	case 'D':
		syslogSeverity = LOG_DEBUG;
		break;
	case 'E':
		syslogSeverity = LOG_ERR;
		break;
	case 'I':
		syslogSeverity = LOG_INFO;
		break;
	case 'N':
		syslogSeverity = LOG_NOTICE;
		break;
	case 'W':
		syslogSeverity = LOG_WARNING;
		break;
	case 'X':
		syslogSeverity = LOG_ERR;
		break;
	default:
		syslogSeverity = LOG_INFO;
		break;
	}

	if (vmapiContextP->printOffset <= 0) {
		sprintf(line, "%d.%lu ", pidTrace, myThread); // add process id and blank
		temp = strlen(line);
		strncpy(line + temp, aLineP, LINESIZE - temp);
	} else {
		prefixL = 2 * vmapiContextP->printOffset;
		if (prefixL > 10)
			prefixL = 10;
		snprintf(line, LINESIZE, "%*.s%s\n", prefixL, prefix, aLineP);
	}

	openlog(NULL, 0, LOG_LOCAL7);
	syslog(syslogSeverity, "%s", line);
	closelog();
}

void outputLine(struct _VmApiInternalContext* vmapiContextP,
		const char* aLineP, int aLogFlag) {

	if (aLogFlag)
		logLine(vmapiContextP, ' ', aLineP);
	listAppendLine(vmapiContextP, &vmapiContextP->outputStream, aLineP);

}

/**
 * This function will read the trace file if found and set all the
 * trace flags to what is in the file. If a flag is not set in the file
 * then that trace is left as it was in the trace structure.
 * If the trace file is not found, then this function only sets the
 * flag in the context to indicate that this function has been called.
 */
void readTraceFile(struct _VmApiInternalContext* vmapiContextP) {
	char pathAndFile[PATHLENGTH + strlen(TRACE_LEVELS_FILE)];
	char* pathP = 0;
	int pathLength = 0;
	unsigned int newTraceFlags[TRACE_AREAS_COUNT];
	unsigned int newTraceFlagFound[TRACE_AREAS_COUNT];
	char lineData[LINESIZE];
	int lineDataLength;
	char line[BUFLEN];
	FILE* traceFileP = 0;
	int keywordIndex;
	int traceSettingIndex;
	int x;
	int rc;
	char * targetPtr;

	// Init new trace flags array
	for (x = 0; x < TRACE_AREAS_COUNT; x++) {
		newTraceFlags[x] = 0;
		newTraceFlagFound[x] = 0;
	}

	// Get the path and file name string for the trace command input
	// Default it to the root .cimvm dir
	memset(pathAndFile, 0, sizeof(pathAndFile));
	strcpy(pathAndFile, TRACE_LEVELS_FILE_DIRECTORY); // initialize to default path
	strcat(pathAndFile, TRACE_LEVELS_FILE); // add on file name

	pathP = getenv("VMAPI"); // Is there a VMAPI environment variable set?
	if (pathP) {
		pathLength = strlen(pathP) + sizeof(TRACE_LEVELS_FILE) + 1;
		if (pathLength > sizeof(pathAndFile)) {
			sprintf(
					line,
					"readTraceFile: Insufficient path buffer size; needed %d, have %d.",
					pathLength, sizeof(pathAndFile));
			errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcContext,
					RsInternalBufferTooSmall, line);
			return;
		}
		strncpy(pathAndFile, pathP, pathLength);
		if (pathAndFile[pathLength - 1] == '/') {
			strcat(pathAndFile, TRACE_LEVELS_FILE);
		} else {
			strcat(pathAndFile, "/");
			strcat(pathAndFile, TRACE_LEVELS_FILE);
		}
	}

	// Now open the file and figure out the trace flags to set/reset
	traceFileP = fopen(pathAndFile, "r");
	if (traceFileP) {
		// Look for keywords and comments in the trace command file
		while (fgets(lineData, sizeof(lineData), traceFileP)) {
			lineDataLength = strlen(lineData);

			// Ignore all 0 length input
			if (0 == lineDataLength) {
				continue;
			}

			// Ignore comment lines - begin with '#'
			if (0 != strncmp(lineData, "#", 1)) {
				// Try to find a keyword match
				keywordIndex = -1;
				for (x = 0; x < TRACE_AREAS_COUNT; x++) {
					if (0 == strncmp(lineData, TRACE_KEYWORDS[x], strlen(
							TRACE_KEYWORDS[x]))) {
						keywordIndex = x;
						break;
					}
				}
				// If no keyword found, log an error
				if (keywordIndex == -1) {
					sprintf(line,
							"readTraceFile: Unknown keyword on line: <%s> \n",
							lineData);
					errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
							RcFunction, RsFunctionUnknown, line);
					return;
				}

				targetPtr = strstr(lineData, "="); // Find the = sign
				if (0 == targetPtr) {
					sprintf(line, "readTraceFile: Missing = on line: <%s> \n",
							lineData);
					errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
							RcFunction, RsFunctionUnknown, line);
					return;
				}

				// Look for a trace settings value
				traceSettingIndex = -1;
				for (x = 0; x < TRACE_LEVELS_COUNT; x++) {
					if (0 != strstr(targetPtr, TRACE_LEVELS[x])) {
						traceSettingIndex = x;
						break;
					}
				}

				// If no trace setting keyword found, log an error
				if (traceSettingIndex == -1) {
					sprintf(
							line,
							"readTraceFile: Unknown trace setting on line: <%s> \n",
							lineData);
					errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
							RcFunction, RsFunctionUnknown, line);
					return;
				}

				// Now set or reset the bits in the new trace flags variable
				if (TRACELEVEL_OFF == traceSettingIndex) // if the trace is to be turned off
				{
					newTraceFlags[keywordIndex] = 0;
					newTraceFlagFound[keywordIndex] = 1;
				} else {
					newTraceFlags[keywordIndex]
							|= TRACE_FLAG_VALUES[traceSettingIndex];
					newTraceFlagFound[keywordIndex] = 1;
				}
			}
		}

		// Set the trace flags pointed to from the context
		// If there was a keyword found otherwise skip setting it
		for (x = 0; x < TRACE_AREAS_COUNT; x++) {
			if (newTraceFlagFound[x]) {
				vmapiContextP->smTraceDetails->traceFlags[x] = newTraceFlags[x];
			}
		}

		fclose(traceFileP);

	}
	vmapiContextP->smTraceDetails->traceFileRead = 1; // Set flag that said we read/tried to read trace settings
	return;
}

char*
strip(char* aLineP, char anOption, char aChar) {

	char* lineP = aLineP;
	char* lastP = 0;
	int lineL = 0;
	int x;

	if (lineP == 0)
		return lineP;

	// Strip leading chars
	if ((anOption == 'L') || (anOption == 'B')) {

		lineL = strlen(lineP);
		if (lineL > 0) {
			for (x = 0; x < lineL; ++x, ++lineP) {
				if (*lineP != aChar)
					break;
			}
		}

	}

	// Strip trailing chars
	if ((anOption == 'T') || (anOption == 'B')) {

		lineL = strlen(lineP);
		if (lineL > 0) {
			lastP = lineP + lineL - 1;
			for (x = lineL; x > 0; --x, --lastP) {
				if (*lastP != aChar)
					break;
				*lastP = 0;
			}
		}

	}

	return lineP;
}

void sysinfo(struct _VmApiInternalContext* vmapiContextP, int anArgc,
		const char** anArgvPP) {

	char buffer[LINESIZE];
	char* bufferP = 0;
	int len = 0;

	FILE* sysinfoP = fopen("/proc/sysinfo", "r");
	if (sysinfoP) {
		rewind(sysinfoP);
		while (bufferP = fgets(buffer, sizeof(buffer), sysinfoP)) {
			len = strlen(bufferP);
			if ((len > 0) && (bufferP[len - 1] == '\n')) {
				bufferP[len - 1] = 0;
			}
			outputLine(vmapiContextP, bufferP, 0);
		}
		fclose(sysinfoP);
	}

}

int testDigit(char aChar) {

	static char digits[] = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' };
	int x;
	for (x = 0; x < (sizeof(digits) / sizeof(digits[0])); ++x) {
		if (aChar == digits[x])
			return 1;
	}

	return 0;

}

const char*
vmApiMessageText(VmApiInternalContext* contextP) {
	const char* noCtxMsgP = "(No message available - VmApi context missing)";
	const char* noMsgP = "(No message available for return/reason code pair)";

	char emsg[LINESIZE];
	int rc = 0;
	int rs = 0;
	int x = 0;

	const char* msgFilenameP = 0;
	FILE* msgFileP = 0;
	char completeMatch[20];
	char rcMatch[20];
	char* msgP = 0;
	char* targetP = 0;
	char* rcP = 0;
	char* rsP = 0;
	char rcS[6];
	char rsS[6];

	if (contextP == 0)
		return noCtxMsgP;

	strcpy(contextP->emsg, noMsgP); // Default

	char filename[sizeof(contextP->path) + 15]; // Adjust once NLS filenames settled

	// Message text comes from the translatable message file
	char resultLine[LINESIZE];
	int resultLineL = 0;
	msgFilenameP = contextGetMessageFilename(contextP, filename,
			sizeof(filename));
	if (msgFilenameP) {
		msgFileP = fopen(msgFilenameP, "r");
		if (msgFileP) {
			// Look for matching 'VMAPI rc reason' in message file
			while (fgets(resultLine, sizeof(resultLine), msgFileP)) {
				resultLineL = strlen(resultLine);
				if (0 != strncmp(resultLine, "#", 1)) { // Ignore comment lines - begin with '#'
					if (0 == strncmp(resultLine, "VMAPI", 5)) { // Only if component is VMAPI                         //strip off second word (rc) and third word (reason)
						targetP = strstr(resultLine, " "); // First blank
						if (targetP) {
							rcP = targetP + 1;
							while (rcP && (*rcP != ' '))
								++rcP; // First blank after rc
							strncpy(rcS, targetP + 1, ((rcP) - (targetP + 1)
									+ 1));
							rc = atoi(rcS);
							rsP = rcP + 1; // Skip blank
							while (rsP && (*rsP != ' '))
								++rsP; // First blank after rs
							strncpy(rsS, rcP + 1, ((rsP) - (rcP + 1) + 1));
							rs = atoi(rsS);

							if ((rc == contextP->rc)
									&& (rs == contextP->reason)) {

								strcpy(contextP->emsg, resultLine);
								break;
							}

							// If no specific reason code matches, use return-code-only
							// message. This requires that the rs=0 message for a specific
							// return code be placed as the last message for that return
							// code in the message file.
							if ((rc == contextP->rc) && (rs == 0)) {
								strcpy(contextP->emsg, resultLine);
								break;
							}
						}
					}
				}

			}
			// If message file can't be opened or msg isn't in file - return
			// with the defaule message set above
		}

	}
	fclose(msgFileP);
	return contextP->emsg;
}

/**
 * Procedure: vmbkendcacheEntryInvalidate
 *
 * Purpose: Mark the specified cache entry as invalid.
 *
 * Input:  pointer to cache path
 *         name of the user ID to invalidate
 * Output:
 *   0  : invalidate performed successfully.
 *   1  : invalidate unsuccessful because stat indicated ENOENT
 *   2  : invalidate unsuccessful because stat got some other error
 *   3  : invalidated by removing cache entry due to fopen failure.
 *   4  : the fopen failed and the remove failed also.
 *
 * Operation:
 * . Generate the name of the cache file based on the inputs
 * . If the cache file can be opened, write 'Invalid' status to beginning
 * . Else try to remove the file
 */
int vmbkendCacheEntryInvalidate(struct _VmApiInternalContext* vmapiContextP,
		char *pathP, char *useridP) {

	char cacheEntry[CACHEENTRYLEN];
	char status[] = "INVALID";
	FILE* cFP;
	int rc;
	int exitrc;
	struct stat statBuf;
	char line[LINESIZE];
	int scaffold = 0; // If scaffolding wanted: No (0) Yes (1)

	int cacheFileFd;
	struct flock fl;

	exitrc = 0; // Initialize to success

	TRACE_ENTRY_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);

	sprintf(cacheEntry, "%s%.8s.direct", pathP, useridP);

	// If the cache file doesn't exist, nothing to do
	rc = stat(cacheEntry, &statBuf);
	if (rc == -1) {
		// Can't continue but check the reason for the stat failing.
		if (errno == ENOENT) {
			TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER,
					TRACELEVEL_DETAILS);
			sprintf(
					line,
					"vmbkendCacheEntryInvalidate:   cache file (%s) does not exist.\n",
					cacheEntry);
			TRACE_END_DEBUG(vmapiContextP, line);

			return 1;
		} else {
			TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER,
					TRACELEVEL_DETAILS);
			sprintf(
					line,
					"vmbkendCacheEntryInvalidate:   stat() on (%s) got errno (0x%x)\n",
					cacheEntry, errno);
			TRACE_END_DEBUG(vmapiContextP, line);

			return 2;
		}
	}

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
	sprintf(
			line,
			"vmbkendCacheEntryInvalidate:  About to invalidate cache entry (%s)\n",
			cacheEntry);
	TRACE_END_DEBUG(vmapiContextP, line);

	rc = remove(cacheEntry);
	if (rc == -1) {
		TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
		sprintf(
				line,
				"vmbkendCacheEntryInvalidate:   remove error on (%s), errno (0x%x)\n",
				cacheEntry, errno);
		TRACE_END_DEBUG(vmapiContextP, line);

		exitrc = 4;
	} else {
		TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
		sprintf(line,
				"vmbkendCacheEntryInvalidate:   removed cache file (%s)\n",
				cacheEntry);
		TRACE_END_DEBUG(vmapiContextP, line);

		exitrc = 3;
	}

	TRACE_EXIT_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);
	return exitrc;
}

int vmbkendCheck(struct _VmApiInternalContext* vmapiContextP) {

	pid_t pid1, pid2, ppid;
	int rc, status;
	char buf[LINESIZE + LINESIZE];
	char line[LINESIZE];

	pthread_t thread;
	pthread_attr_t attr;

	rc = 0;

	int backendSemaphoreValue = 0;
	void *vmapiPtr = NULL;

	// Check if backend already running and return in this case
	backendSemaphoreValue = semctl(vmapiContextP->semId, BackendSemaphoreIndex,
			GETVAL, 0);

	if (1 != backendSemaphoreValue) {
		TRACE_START(vmapiContextP,
				TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
				TRACELEVEL_DETAILS);
		sprintf(line,
				"vmbkendCheck: Backend apparently running; passing backend start \n");
		TRACE_END_DEBUG(vmapiContextP, line);
		vmapiContextP->checkBackendFlag = 1; // Mark the backend as running
		return rc; // Backend running
	}

	// If vmbkend daemon not started, start it
	// Create a pthread and call the vmbkendMain
	vmapiPtr = (void*) dlopen(VMAPILIB, RTLD_NOW); // Load the library

	if (vmapiPtr == NULL) {
		TRACE_START(vmapiContextP,
				TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
				TRACELEVEL_DETAILS);
		sprintf(line, "vmbkendCheck: Loading library failed %s .\n", dlerror());
		TRACE_END_DEBUG(vmapiContextP, line);
	}

	pthread_attr_init(&attr);

	TRACE_START(vmapiContextP,
			TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
			TRACELEVEL_DETAILS);
	sprintf(line, "vmbkendCheck: Creating a pthread \n");
	TRACE_END_DEBUG(vmapiContextP, line);

	pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

	pthread_mutex_lock(&mutex);
	rc = pthread_create(&thread, &attr, vmbkendMain, (void *) vmapiContextP);

	pthread_cond_wait(&thread_initialized_cv, &mutex);

	TRACE_START(vmapiContextP,
			TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
			TRACELEVEL_DETAILS);
	sprintf(line, "vmbkendCheck: pthread created with rc = %d \n", rc);
	TRACE_END_DEBUG(vmapiContextP, line);

	return 0;
}

/**
 * Procedure: vmbkendgetCachePath
 *
 * Purpose: Return the path to the $VMAPI/.vmapi/cache directory, where
 *          $VMAPI is the VMAPI environment variable.  If VMAPI is not
 *          defined, the current working directory '.' is used.
 *
 *          An example of the directory returned is as follows (note the
 *          slash at the end):
 *
 *          /foo/bar/.vmapi/cache/
 *
 * Input:  pointer to string for where to put the cache path
 * Output: none
 *
 * Operation:
 * . Get VMAPI environment variable
 * . Pull together the cache directory using the VMAPI value.
 *
 */
void vmbkendGetCachePath(struct _VmApiInternalContext* vmapiContextP,
		char *pathP) {

	char *getenvP = 0;
	char line[LINESIZE];
	int retValue;

	TRACE_ENTRY_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);

	// Obtain path to $VMAPI/.vmapi/cache
	// If no (context) path string call to initialize things.
	if (1 != vmapiContextP->contextCreatedFlag) {
		retValue = initializeThreadSemaphores(vmapiContextP, "", 1); // Create context using no name to override current context name
		if (retValue) {
			sprintf(
					line,
					"vmbkendGetCachePath(): context reserve() returned error: %d\n",
					retValue);
			errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
					RsUnexpected, line);
			return;
		}
	}
	strcpy(pathP, vmapiContextP->path);

	strcat(pathP, CACHE_DIRECTORY);

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
	sprintf(line, "vmbkendGetCachePath:  The cache path is (%s)\n", pathP);
	TRACE_END_DEBUG(vmapiContextP, line);

	TRACE_EXIT_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);
	return;

}

void *vmbkendMain(void *context) {

	int argIndex;
	int serverSock;
	struct sockaddr_in serverSockaddr;
	struct sockaddr_in serverSockaddr1;
	struct sockaddr_in clientSockaddr;
	struct sockaddr_in notificationSocketInfo;
	struct sockaddr_in previousSockaddr;

	int socklen;
	int rc;
	int clientLen;
	char readBuffer[BUFLEN];
	char userID[BUFLEN];
	unsigned int useridLength;
	int bytesRead;
	struct sembuf operations[1];

	char cmd[BUFLEN];
	unsigned int cmdLength;
	char subData[BUFLEN];
	unsigned int subDataLength;
	struct in_addr inaddr;
	int x;

	int clientSock;
	int totalRead;

	char hostid[20];
	unsigned char *ipP = 0;
	char path[BUFLEN + 1];
	char cachePath[BUFLEN + 1];
	char userListPath[BUFLEN + 1];

	time_t ltime;
	char line[LINESIZE + LINESIZE];
	pid_t pid;

	char ourIpAddr[20];
	unsigned int ourPort;
	smMemoryGroupContext localMemoryGroup;
	smMemoryGroupContext * saveMemoryGroup;
	vmApiAsynchronousNotificationEnableDmOutput * ptrEnableOutputData;
	vmApiAsynchronousNotificationDisableDmOutput * ptrDisableOutputData;

	VmApiInternalContext *vmapiContextP;

	VmApiInternalContext vmapiContext;
	smMemoryGroupContext memContext;
	extern struct _smTrace externSmapiTraceFlags;
	int smrc;
	pthread_mutex_lock(&mutex);

	// Expand the macro for time being
	memset(&vmapiContext, 0, sizeof(*(&vmapiContext)));
	memset(&memContext, 0, sizeof(*(&memContext)));
	(&vmapiContext)->memContext = &memContext;
	(&vmapiContext)->smTraceDetails
			= (struct _smTrace *) &externSmapiTraceFlags;
	smrc = smMemoryGroupInitialize(&vmapiContext);

	if (0 == smrc) {
		readTraceFile(&vmapiContext);
	} else {
		logLine(&vmapiContext, 'E', "Unexpected smMemoryGroupInitializeError!");
	}

	vmapiContextP = &vmapiContext;

	TRACE_START(vmapiContextP,
			TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
			TRACELEVEL_DETAILS);
	sprintf(line, "Inside back end thread \n");
	TRACE_END_DEBUG(vmapiContextP, line);

	if (1 != vmapiContextP->contextCreatedFlag) {
		rc = initializeThreadSemaphores(vmapiContextP, "", 1); // create context using no name to override current context name
		TRACE_START(vmapiContextP,
				TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
				TRACELEVEL_DETAILS);
		sprintf(line, "Inside back end thread retValue = %d \n", rc);
		TRACE_END_DEBUG(vmapiContextP, line);
	}

	// Indicate this is the backend
	vmapiContextP->isBackend = 1;

	// Obtain the Backend semaphore to before manipulating context related stuff
	operations[0].sem_num = BackendSemaphoreIndex;
	operations[0].sem_op = -1;
	operations[0].sem_flg = SEM_UNDO;
	rc = semop(vmapiContextP->semId, operations, sizeof(operations)
			/ sizeof(operations[0]));
	if (rc < 0) {
		TRACE_START(vmapiContextP,
				TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
				TRACELEVEL_DETAILS);
		sprintf(line,
				"vmbkendMain: semop (decrement) failed, errno=%d text: %s",
				errno, strerror(errno));
		TRACE_END_DEBUG(vmapiContextP, line);
	}

	// OK: ready to go
	time(&ltime);
	TRACE_START(vmapiContextP,
			TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
			TRACELEVEL_DETAILS);
	sprintf(line, "vmbkendMain: Entry to --> at %s", ctime(&ltime));
	TRACE_END_DEBUG(vmapiContextP, line);

	// Build path to the cache directory.
	memset(path, 0, sizeof(cachePath));
	vmbkendGetCachePath(vmapiContextP, cachePath);

	// Call routine to remove the cache.
	vmbkendRemoveEntireCache(vmapiContextP, cachePath);

	// Do the necessary socket server setup
	serverSock = socket(AF_INET, SOCK_DGRAM, 0);
	exit_if_error(Socket, serverSock, serverSock);

	memset(&serverSockaddr, 0, sizeof serverSockaddr);

	// Read and use any previous port number that may have
	// been set by a previous run of vmbkend.  If no previous
	// run or error, the value zero is returned.
	vmbkendSockaddrFileInfo(vmapiContextP, 0, &previousSockaddr);
	serverSockaddr.sin_port = previousSockaddr.sin_port;
	serverSockaddr.sin_family = AF_INET;
	serverSockaddr.sin_addr.s_addr = htonl(INADDR_ANY);

	rc = bind(serverSock, (struct sockaddr *) &serverSockaddr,
			sizeof serverSockaddr);

	if (-1 == rc) { // Bind failure
		if (0 == serverSockaddr.sin_port) {
			// The bind for an ephemeral port failed.
			exit_if_error(Bind, rc, serverSock);
		} else {
			// We used a previous port and this failed,
			// Retry the bind for any ephemeral port.
			memset(&serverSockaddr, 0, sizeof serverSockaddr);
			serverSockaddr.sin_port = 0;
			serverSockaddr.sin_addr.s_addr = htonl(INADDR_ANY);
			TRACE_START(vmapiContextP,
					TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
					TRACELEVEL_DETAILS);
			TRACE_END_DEBUG(vmapiContextP,
					"vmbkendMain:  Retrying bind for sin_port <0>\n");
			rc = bind(serverSock, (struct sockaddr *) &serverSockaddr,
					sizeof serverSockaddr);

			exit_if_error(Bind, rc, serverSock);
		}
	}

	memset(&serverSockaddr1, 0, sizeof serverSockaddr1);
	socklen = sizeof serverSockaddr1;

	rc
			= getsockname(serverSock, (struct sockaddr *) &serverSockaddr1,
					&socklen);
	exit_if_error(Getsockname, rc, serverSock);

	// Show the IP address for our system
	get_myaddress(&notificationSocketInfo);

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
	// Show what port number we are listening on
	sprintf(line, "vmbkendMain: Listening on %s:%u", inet_ntoa(
			notificationSocketInfo.sin_addr), (unsigned) ntohs(
			serverSockaddr1.sin_port));
	TRACE_END_DEBUG(vmapiContextP, line);

	// Set port for notification
	notificationSocketInfo.sin_port = serverSockaddr1.sin_port;

	// If we used different information from a previous run
	// then:
	// - write new info to the file PORT_FILENAME
	// - unregister old info with the directory manager.
	if ((previousSockaddr.sin_port != notificationSocketInfo.sin_port)
			|| (previousSockaddr.sin_addr.s_addr
					!= notificationSocketInfo.sin_addr.s_addr)) {

		// Write new info to PORT_FILENAME
		vmbkendSockaddrFileInfo(vmapiContextP, 1, &notificationSocketInfo);

		// If previous registration, unregister it
		if (0 != previousSockaddr.sin_port) {
			sprintf(ourIpAddr, "%s", inet_ntoa(previousSockaddr.sin_addr));
			ourPort = previousSockaddr.sin_port;

			saveMemoryGroup = vmapiContextP->memContext;
			vmapiContextP->memContext = &localMemoryGroup;
			smMemoryGroupInitialize(vmapiContextP);

			rc = smAsynchronous_Notification_Disable_DM(vmapiContextP, "", // IUCV userID and password not needed
					0, // Password length
					"", // Password
					"ALL", // Target identifier
					1, // Entity_type directory
					2, // UDP communication_type,
					ourPort, // Port_number,
					ourIpAddr, // IP_address string,
					1, // ASCII encoding,
					0, // Subscriber_data_length,
					"", // Subscriber_data,
					&ptrDisableOutputData);
			if (0 != rc || 0 != ptrDisableOutputData->returnCode) {
				TRACE_START(vmapiContextP,
						TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
						TRACELEVEL_DETAILS);
				sprintf(
						line,
						"vmbkendMain: call to asynch unregister got rc1 %d rc2 %d \n",
						rc, ptrDisableOutputData->returnCode);
				TRACE_END_DEBUG(vmapiContextP, line);
				smMemoryGroupFreeAll(vmapiContextP);
				smMemoryGroupTerminate(vmapiContextP);
				vmapiContextP->memContext = saveMemoryGroup;
				close(serverSock);
				pthread_exit(NULL);
			}
			smMemoryGroupFreeAll(vmapiContextP);
			smMemoryGroupTerminate(vmapiContextP);
			vmapiContextP->memContext = saveMemoryGroup;
		}
	} // Used different port number

	// Call asynchronous notify RPC to register with the
	// directory manager.
	sprintf(ourIpAddr, "%s", inet_ntoa(notificationSocketInfo.sin_addr));
	ourPort = notificationSocketInfo.sin_port;

	saveMemoryGroup = vmapiContextP->memContext;
	vmapiContextP->memContext = &localMemoryGroup;
	smMemoryGroupInitialize(vmapiContextP);

	rc = smAsynchronous_Notification_Enable_DM(vmapiContextP, "", // IUCV userID and password not needed
			0, // Password length
			"", // Password
			"ALL", // Target identifier
			1, // Entity_type directory
			1, // Include subscription type
			2, // UDP subscription_type
			ourPort, // Port_number
			ourIpAddr, // IP_address
			1, // ASCII encoding
			0, // Subscriber_data_length
			"", // Subscriber_data
			&ptrEnableOutputData);
	if (0 == rc && 0 != ptrEnableOutputData->returnCode) {
		TRACE_START(vmapiContextP,
				TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
				TRACELEVEL_DETAILS);
		sprintf(
				line,
				"vmbkendMain: call to asynch register got rc1 %d rc2 %d and rs %d\n",
				rc, ptrEnableOutputData->returnCode,
				ptrEnableOutputData->reasonCode);
		TRACE_END_DEBUG(vmapiContextP, line);

		// If Subscription exists... Do not do anything.
		if (!ptrEnableOutputData->returnCode == 428) {
			smMemoryGroupFreeAll(vmapiContextP);
			smMemoryGroupTerminate(vmapiContextP);
			vmapiContextP->memContext = saveMemoryGroup;
			close(serverSock);
			pthread_exit(NULL);
		}
	} else if (0 != rc) {
		smMemoryGroupFreeAll(vmapiContextP);
		smMemoryGroupTerminate(vmapiContextP);
		vmapiContextP->memContext = saveMemoryGroup;
		close(serverSock);
		pthread_exit(NULL);

	}

	smMemoryGroupFreeAll(vmapiContextP);
	smMemoryGroupTerminate(vmapiContextP);
	vmapiContextP->memContext = saveMemoryGroup;

	// Wait for and handle incoming requests from the
	// directory manager.
	pthread_cond_signal(&thread_initialized_cv);
	pthread_mutex_unlock(&mutex);
	for (;;) {
		time(&ltime);

		// UDP
		TRACE_START(vmapiContextP,
				TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
				TRACELEVEL_DETAILS);
		sprintf(line, "vmbkendMain:  About to receive on  %s", ctime(&ltime));
		TRACE_END_DEBUG(vmapiContextP, line);

		memset(readBuffer, 0, sizeof readBuffer);
		memset(&clientSockaddr, 0, sizeof clientSockaddr);
		clientLen = sizeof clientSockaddr;
		bytesRead = 0;
		useridLength = 0;

		bytesRead = recvfrom(serverSock, readBuffer, sizeof(readBuffer), 0,
				(struct sockaddr *) &clientSockaddr, &clientLen);

		if (bytesRead == -1) {
			TRACE_START(vmapiContextP,
					TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
					TRACELEVEL_DETAILS);
			sprintf(line, "vmbkendMain:  recvfrom got errno %d\n", errno);
			TRACE_END_DEBUG(vmapiContextP, line);
			break;
		}
		continue_if_error(Recvfrom, bytesRead, bytesRead);

		strcpy(path, cachePath);

		TRACE_START(vmapiContextP,
				TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
				TRACELEVEL_DETAILS);
		sprintf(line, "vmbkendMain:  Read %d bytes from %s at time: %s\n",
				bytesRead, inet_ntoa(clientSockaddr.sin_addr), ctime(&ltime));
		TRACE_END_DEBUG(vmapiContextP, line);

		// If the message is too small, this is an error, go get
		// the next message.
		if (bytesRead <= LENGTH_OF_USERID_LENGTH_FIELD) {
			TRACE_START(vmapiContextP,
					TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
					TRACELEVEL_DETAILS);
			sprintf(line, "vmbkendMain:  Message is too short");
			TRACE_END_DEBUG(vmapiContextP, line);
			continue;
		}

		// Pull out the user ID length
		useridLength = *(int *) &readBuffer;
		useridLength = ntohl(useridLength);

		// Get the user ID
		memset(userID, 0, sizeof userID);
		strncpy(userID, readBuffer + 4, useridLength);

		TRACE_START(vmapiContextP,
				TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
				TRACELEVEL_DETAILS);
		sprintf(line,
				"vmbkendMain:  User ID length is >%d< and User ID is >%s<\n",
				useridLength, userID);
		TRACE_END_DEBUG(vmapiContextP, line);

		// Get the command length
		cmdLength = *(int *) (readBuffer + 4 + useridLength);
		cmdLength = ntohl(cmdLength);

		// Get the command
		memset(cmd, 0, sizeof cmd);
		strncpy(cmd, readBuffer + 4 + useridLength + 4, cmdLength);

		TRACE_START(vmapiContextP,
				TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
				TRACELEVEL_DETAILS);
		sprintf(line, "vmbkendMain:  Command is >%s<\n", cmd);
		TRACE_END_DEBUG(vmapiContextP, line);

		if (strcasecmp(cmd, "add") == 0 || strcasecmp(cmd, "purge") == 0) {
			strcpy(userListPath, cachePath);
			strcat(userListPath, "users.list");
			rc = remove(userListPath);
			if (rc == -1) {
				TRACE_START(vmapiContextP,
						TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
						TRACELEVEL_DETAILS);
				sprintf(line,
						"vmbkendMain:   remove error on (%s), errno (0x%x)\n",
						userListPath, errno);
				TRACE_END_DEBUG(vmapiContextP, line);
			}
		}

		// Get the subscriber data length
		subDataLength
				= *(int *) (readBuffer + 4 + useridLength + 4 + cmdLength);
		subDataLength = ntohl(subDataLength);

		// Invalidate the cache entry
		TRACE_START(vmapiContextP,
				TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
				TRACELEVEL_DETAILS);
		sprintf(line, "vmbkendMain:  Invalidating cache for user ID (%s)\n",
				userID);
		TRACE_END_DEBUG(vmapiContextP, line);

		for (x = 0; x < useridLength; ++x) {
			userID[x] = tolower(userID[x]);
		}

		vmbkendCacheEntryInvalidate(vmapiContextP, path, userID);

		// Clear out the .scan files
	}

	// Call asynchronous notify RPC to unregister with the
	// directory manager.
	sprintf(ourIpAddr, "%s", inet_ntoa(notificationSocketInfo.sin_addr));
	ourPort = notificationSocketInfo.sin_port;

	saveMemoryGroup = vmapiContextP->memContext;
	vmapiContextP->memContext = &localMemoryGroup;
	smMemoryGroupInitialize(vmapiContextP);

	rc = smAsynchronous_Notification_Disable_DM(vmapiContextP, "", // IUCV userID and password not needed
			0, // Password length
			"", // password
			"ALL", // Target identifier
			1, // Entity_type directory
			2, // UDP communication_type,
			ourPort, // Port_number,
			ourIpAddr, // IP_address,
			1, // ASCII encoding,
			0, // Subscriber_data_length,
			"", // Subscriber_data,
			&ptrDisableOutputData);
	if (0 != rc || 0 != ptrDisableOutputData->returnCode) {
		TRACE_START(vmapiContextP,
				TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
				TRACELEVEL_DETAILS);
		sprintf(line,
				"vmbkendMain: call to asynch unregister got rc1 %d rc2 %d \n",
				rc, ptrDisableOutputData->returnCode);
		TRACE_END_DEBUG(vmapiContextP, line);
		smMemoryGroupFreeAll(vmapiContextP);
		smMemoryGroupTerminate(vmapiContextP);
		vmapiContextP->memContext = saveMemoryGroup;
		close(serverSock);
		pthread_exit(NULL);
	}

	smMemoryGroupFreeAll(vmapiContextP);
	smMemoryGroupTerminate(vmapiContextP);
	vmapiContextP->memContext = saveMemoryGroup;

	// Close the server socket
	TRACE_START(vmapiContextP,
			TRACEAREA_BACKGROUND_DIRECTORY_NOTIFICATION_THREAD,
			TRACELEVEL_DETAILS);
	TRACE_END_DEBUG(vmapiContextP,
			"vmbkendMain:  About to close() server socket\n");
	rc = close(serverSock);
	exit_if_error(Close, rc, rc);
	pthread_exit(NULL);
}

/**
 * Procedure: vmbkendremoveCachedScanFiles
 *
 * Purpose: Remove the ***.scan files.
 *
 * Input:  pointer to cache path
 * Output: none
 *
 * Operation:
 * . Build the rm command from the input path
 * . Issue the rm command via system()
 */
int vmbkendRemoveCachedScanFiles(struct _VmApiInternalContext* vmapiContextP,
		char *pathP) {

	char command[300];
	char line[LINESIZE];

	TRACE_ENTRY_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);

	// Build the remove command
	sprintf(command, "rm -f %s%s", pathP, ALL_SCAN_FILES);

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
	sprintf(line,
			"vmbkendRemoveCachedScanFiles:  About to issue: system(%s)\n",
			command);
	TRACE_END_DEBUG(vmapiContextP, line);

	if (system(command)) {
		TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
		sprintf(
				line,
				"vmbkendRemoveCachedScanFiles:  Error removing scan files, errno 0x%X: reason(%s)\n",
				errno, strerror(errno));
		TRACE_END_DEBUG(vmapiContextP, line);
	}

	TRACE_EXIT_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);

	return 0;

}

/**
 * Procedure: vmbkendremoveEntireCache
 *
 * Purpose: Remove all cache entries from the cache directory.
 *
 * Input:  pointer to the cache directory
 * Output: none
 *
 * Operation:
 * . Build rm command from input cache directory
 * . Issue the rm command via system()
 */
void vmbkendRemoveEntireCache(struct _VmApiInternalContext* vmapiContextP,
		char *cachePathP) {

	char command[300];
	char line[LINESIZE];

	TRACE_ENTRY_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);

	// Build the remove command
	sprintf(command, "rm -rf %s*", cachePathP);

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
	sprintf(line, "vmbkendRemoveEntireCache:  About to issue: system(%s)\n",
			command);
	TRACE_END_DEBUG(vmapiContextP, line);

	if (system(command)) {
		TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
		sprintf(
				line,
				"vmbkendRemoveEntireCache:  Error removing file, errno 0x%X: reason(%s)\n",
				errno, strerror(errno));
		TRACE_END_DEBUG(vmapiContextP, line);
	}

	TRACE_EXIT_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);
	return;
}

/**
 * Procedure: vmbkendSockaddrFileInfo
 *
 * Purpose: Save new or retrieve previous bind information to or from
 *          the file defined by $VMAPI/PORT_FILENAME.
 *
 * Input:  int readOrWrite : 0 = read it; 1 = write it
 *         sockaddr_in saddr: If readOrWrite is read, then on input this is
 *             is the address of where to store the retrieved bind info.
 *             If readOrWrite is write, then on input this is the address of
 *             the sockaddr_in containing the bind info to save.
 *
 * Output: rc = 0 ; success; if read then saddr contains the read value.
 *                           if write, then the file is updated.
 *         rc = -1 ; failure; if read, saddr value returned is zeroes.
 *                            if write, saddr is unchanged.
 *
 * Operation:
 * . Get the path to the file $VMAPI/.vmapi/PORT_FILENAME
 * . Open the file read or write based on the value of readOrWrite input
 * . If error,
 *   - if read, set saddr to zeroes
 *   - return -1
 * . If read then read the info
 *   Else write the info
 * . Close the file.
 */
int vmbkendSockaddrFileInfo(struct _VmApiInternalContext* vmapiContextP,
		int readOrWrite, struct sockaddr_in *saddr) {

	FILE *fileP = (FILE *) NULL;
	char fName[BUFLEN + 1];
	char *getenvP = 0;
	int rc = 0;
	char line[LINESIZE];

	TRACE_ENTRY_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);

	strcpy(fName, vmapiContextP->path);
	strcat(fName, PORT_FILENAME);

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
	sprintf(line, "vmbkendSockaddrFileInfo:  PORT_FILENAME %s \n", fName);
	TRACE_END_DEBUG(vmapiContextP, line);

	errno = 0;
	if (0 == readOrWrite) { // Read
		// If error reading record, return saddr value of zeroes
		memset(saddr, 0, sizeof(struct sockaddr_in));
		fileP = fopen(fName, "r");
	} else {
		fileP = fopen(fName, "w");
	}

	if (fileP == (FILE *) NULL) {
		TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
		sprintf(line,
				"vmbkendSockaddrFileInfo:  Errno %d opening %s for %s()\n",
				errno, fName, (readOrWrite == 0 ? "read" : "write"));
		TRACE_END_DEBUG(vmapiContextP, line);

		rc = -1;
		goto exit_error2;
	}

	if (readOrWrite == 0) { // read
		if (EOF == fscanf(fileP, "%x:%hu", &(saddr->sin_addr.s_addr),
				&(saddr->sin_port))) {
			// If error reading record, return saddr value of zeroes
			memset(saddr, 0, sizeof(struct sockaddr_in));
			TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER,
					TRACELEVEL_DETAILS);
			sprintf(line,
					"vmbkendSockaddrFileInfo:  Errno %d reading file %s\n",
					errno, fName);
			TRACE_END_DEBUG(vmapiContextP, line);

			rc = -1;
			goto exit_error1;
		}
		TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
		sprintf(line, "vmbkendSockaddrFileInfo:  Read %x:%hu\n",
				saddr->sin_addr.s_addr, saddr->sin_port);
		TRACE_END_DEBUG(vmapiContextP, line);

	} else { // Write
		if (-1 == fprintf(fileP, "%x:%hu", saddr->sin_addr.s_addr,
				saddr->sin_port)) {
			TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER,
					TRACELEVEL_DETAILS);
			sprintf(
					line,
					"vmbkendSockaddrFileInfo:  Errno %d writing %x:%hu to %s\n",
					errno, saddr->sin_addr.s_addr, saddr->sin_port, fName);
			TRACE_END_DEBUG(vmapiContextP, line);

			rc = -1;
			goto exit_error1;
		}
		TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
		sprintf(line, "vmbkendSockaddrFileInfo:  Wrote %x:%hu\n",
				saddr->sin_addr.s_addr, saddr->sin_port);
		TRACE_END_DEBUG(vmapiContextP, line);
	}

	exit_error1: if (EOF == fclose(fileP)) {
		TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
		sprintf(line, "vmbkendSockaddrFileInfo:  Errno %d closing file %s()\n",
				errno, fName);
		TRACE_END_DEBUG(vmapiContextP, line);
	}
	exit_error2: TRACE_EXIT_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);

	return (rc);
}

void waitForPendingWorkunits(struct _VmApiInternalContext* vmapiContextP,
		int waitIntervalInSeconds) // 0 = wait forever
{

	int argN = 2;
	const char* args[2];
	char line[LINESIZE];
	int maxRc = 0;
	int maxReason = 0;
	int x = 0;
	int workunitsPending = 1;
	int workunitId;
	int duration;
	int interval;
	int rc;
	time_t startTime;

	smMemoryGroupContext localMemoryGroup;
	smMemoryGroupContext * saveMemoryGroup;
	vmApiQueryAsynchronousOperationDmOutput * ptrQueryAsynchOutputData;

	// Duration == 0 is assumed as infinite duration
	duration = waitIntervalInSeconds;
	time(&startTime);

	while (workunitsPending && duration >= 0) {

		workunitsPending = 0;

		for (x = 0; (x < (sizeof(vmapiContextP->pendingWorkunits)
				/ sizeof(vmapiContextP->pendingWorkunits[0]))); ++x) {

			if (vmapiContextP->pendingWorkunits[x] == 0)
				continue;

			workunitId = vmapiContextP->pendingWorkunits[x];

			vmapiContextP->rc = 0;
			vmapiContextP->reason = 0;

			saveMemoryGroup = vmapiContextP->memContext;
			vmapiContextP->memContext = &localMemoryGroup;

			smMemoryGroupInitialize(vmapiContextP);
			if (0 != (rc = smQuery_Asychronous_Operation_DM(vmapiContextP,
					"", // Userid is not required for IUCV
					0, // Length 0; no password of IUCV
					"", // No password
					vmapiContextP->useridForAsynchNotification, workunitId,
					&ptrQueryAsynchOutputData))) {
			}

			vmapiContextP->rc = ptrQueryAsynchOutputData->returnCode;
			vmapiContextP->reason = ptrQueryAsynchOutputData->reasonCode;

			// Since the only result data we care about is the return and reason codes, we can
			// free any working memory now.
			smMemoryGroupFreeAll(vmapiContextP);
			smMemoryGroupTerminate(vmapiContextP);
			vmapiContextP->memContext = saveMemoryGroup;

			// check for finished operation
			if ((vmapiContextP->rc == 0) && (vmapiContextP->reason == 100)) {
				vmapiContextP->pendingWorkunits[x] = 0;
				continue;
			}

			// Check for ongoing operation
			if ((vmapiContextP->rc == 0) && (vmapiContextP->reason == 104)) {
				workunitsPending = 1; // At least this one
				continue;
			}

			// Check for failed operation
			if ((vmapiContextP->rc == 0) && (vmapiContextP->reason == 108)) {
				vmapiContextP->rc = 200; // Set failed image operation error code
				vmapiContextP->reason = 0;
			}

			// Here when an error occurred
			// The workunit is assumed to be either finished or failed,
			// that is it is not assumed to be ongoing any more.
			if ((vmapiContextP->rc == maxRc) && (vmapiContextP->reason
					> maxReason)) {
				maxReason = vmapiContextP->reason;
			} else if (vmapiContextP->rc > maxRc) {
				maxRc = vmapiContextP->rc;
				maxReason = vmapiContextP->reason;
			}

		}

		interval = SleepInterval;
		if ((duration > 0) && (interval > duration))
			interval = duration;

		if (workunitsPending && (interval > 0)) {

			sleep(interval);

		}

		if (duration > 0) {
			duration -= interval;
			// Since == 0 is assumed to be indefinite set -1 in this case
			if (duration == 0)
				duration = -1;
		}

	}

	// Quickfix to overcome problems on tmcc system
	sleep(5);

	vmapiContextP->rc = maxRc;
	vmapiContextP->reason = maxReason;

}

/**
 * A valid cache file has good time interval and no "INVALID" PAS0304
 * file is closed for stat to work
 */
int cacheFileValid(struct _VmApiInternalContext* vmapiContextP,
		const char* cFNameP) {

	int defaultTimeLimit = 5000; // Seconds = approx 1.5 hours
	int timeLimit = 0;
	struct stat statbuf;
	time_t currentTime;
	double fileAgeSeconds = 0;
	time_t fileTime = 0;
	unsigned int x = 0;

	if (getenv("EPP_CACHE_TIMELIMIT")) {
		timeLimit = atoi(getenv("EPP_CACHE_TIMELIMIT"));
	} else {
		timeLimit = defaultTimeLimit;
	}

	if (-1 == time(&currentTime))
		return 0; // Current time failed

	if (-1 == stat(cFNameP, &statbuf))
		return 0; // Stat failed

	fileTime = statbuf.st_mtime;

	fileAgeSeconds = difftime(currentTime, fileTime);

	if ((fileAgeSeconds < 0) || (fileAgeSeconds > timeLimit))
		return 0;

	return 1;
}
