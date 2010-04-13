// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "smSocket.h"
#include "vmapiImage.h"
#include "smapiTableParser.h"
#include <stdlib.h>
#include <string.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <errno.h>

#define PARSER_TABLE_NAME     Image_Name_Query_DM_Layout
#define OUTPUT_STRUCTURE_NAME vmApiImageNameQueryDmOutput

/**
 * Image_Name_Query_DM SMAPI interface
 */
int smImage_Name_Query_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, vmApiImageNameQueryDmOutput ** outData) {
	const char * const functionName = "Image_Name_Query_DM";
	tableParserParms parserParms;
	int tempSize;
	char * cursor;
	char * stringCursor; // Used for outData string area pointer
	int arrayCount;
	int totalStringSize;
	int rc = 0;
	int sockDesc;
	int requestId;

	int inputSize = 4 + 4 + strlen(functionName) + 4 + strlen(userid) + 4
			+ passwordLength + 4 + strlen(targetIdentifier);
	char * inputP = 0;
	char * smapiOutputP = 0;
	int i;
	int temp;
	char *imageName;
	vmApiImageName *nameList;

	FILE* cacheFileP = 0;
	char resultLine[10];
	int resultLineL = 0;
	char cachePath[BUFLEN + 1];
	int cacheFileFD;
	struct flock fl;
	int recordCount = 0;
	char traceLine[LINESIZE + 100];
	int dataReadFromCache = 0;

	TRACE_ENTRY_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);
	// Read from the cache file, if exists.

	memset(cachePath, 0, sizeof(cachePath));
	strcpy(cachePath, "/var/opt/ibm/zvmmap/.vmapi/.cache/");
	strcat(cachePath, "users.list");

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER, TRACELEVEL_DETAILS);
	sprintf(traceLine, "Cache file to look for: <%.*s> \n", LINESIZE, cachePath);
	TRACE_END_DEBUG(vmapiContextP, traceLine);

	if (cachePath) {
		if (cacheFileValid(vmapiContextP, cachePath)) {
			cacheFileP = fopen(cachePath, "r");

			TRACE_START(vmapiContextP, TRACEAREA_CACHE, TRACELEVEL_DETAILS);
			sprintf(traceLine, "Cache file pointer opened for read: %p \n",
					cacheFileP);
			TRACE_END_DEBUG(vmapiContextP, traceLine);

			if (cacheFileP != NULL) {
				cacheFileFD = fileno(cacheFileP);

				TRACE_START(vmapiContextP, TRACEAREA_CACHE, TRACELEVEL_DETAILS);
				sprintf(traceLine,
						"Cache file integer descriptor value: %d \n",
						cacheFileFD);
				TRACE_END_DEBUG(vmapiContextP, traceLine);

				if (cacheFileFD != -1) {
					// Lock the file while reading, so no one else is writing into it
					fl.l_type = F_RDLCK;
					fl.l_whence = SEEK_SET;
					fl.l_start = 0;
					fl.l_len = 0;

					// Try to get the lock, if the file is in use by some other process, fetch the information from directory
					if (fcntl(cacheFileFD, F_SETLK, &fl) != -1) {
						TRACE_START(vmapiContextP, TRACEAREA_CACHE,
								TRACELEVEL_DETAILS);
						sprintf(traceLine, "Cache file read lock obtained.\n");
						TRACE_END_DEBUG(vmapiContextP, traceLine);

						*outData = smMemoryGroupAlloc(vmapiContextP,
								sizeof(vmApiImageNameQueryDmOutput));
						nameList = smMemoryGroupAlloc(vmapiContextP,
								sizeof(nameList));

						if (nameList == 0 || *outData == 0) {
							sprintf(traceLine,
									"***Error trying to obtain memory for cache records.\n");
							errorLog(vmapiContextP, __func__, TO_STRING(
									__LINE__), RcRuntime, RsNoMemory, traceLine);
							return MEMORY_ERROR;
						}

						while (fgets(resultLine, sizeof(resultLine), cacheFileP)) {
							resultLineL = strlen(resultLine);
							TRACE_START(vmapiContextP, TRACEAREA_CACHE,
									TRACELEVEL_DETAILS);
							sprintf(traceLine,
									"Found the  user <%s>  in Cache \n",
									resultLine);
							TRACE_END_DEBUG(vmapiContextP, traceLine);

							recordCount++;
							if (resultLineL > 0) {
								if (resultLine[resultLineL - 1] == '\n') {
									--resultLineL;
									resultLine[resultLineL] = 0;
								}
							}
							imageName = smMemoryGroupAlloc(vmapiContextP,
									resultLineL);
							if (imageName == 0) {
								sprintf(traceLine,
										"***Error trying to obtain memory for cache records.\n");
								errorLog(vmapiContextP, __func__, TO_STRING(
										__LINE__), RcRuntime, RsNoMemory,
										traceLine);
								return MEMORY_ERROR;
							}

							strcpy(imageName, resultLine);
							dataReadFromCache = 1;

							if (recordCount > 1) {
								nameList = smMemoryGroupRealloc(vmapiContextP,
										(void *) nameList, recordCount
												* sizeof(nameList));
								if (nameList == 0) {
									sprintf(
											traceLine,
											"***Error trying to obtain realloc memory for cache records of size %d.\n",
											recordCount * sizeof(nameList));
									errorLog(vmapiContextP, __func__,
											TO_STRING(__LINE__), RcRuntime,
											RsNoMemory, traceLine);
									return MEMORY_ERROR;
								}
							}
							nameList[recordCount - 1].imageName = imageName;
						}

						(*outData) -> nameList = nameList;
						(*outData) -> nameCount = recordCount;
						(*outData) -> common.returnCode
								= (*outData) -> common.reasonCode = 0;

						// Unlock the file
						fl.l_type = F_UNLCK;
						fl.l_whence = SEEK_SET;
						fl.l_start = 0;
						fl.l_len = 0;
						TRACE_START(vmapiContextP, TRACEAREA_CACHE,
								TRACELEVEL_DETAILS);
						sprintf(traceLine,
								"Cache file read lock to be unlocked.\n");
						TRACE_END_DEBUG(vmapiContextP, traceLine);

						if (-1 == fcntl(cacheFileFD, F_SETLK, &fl)) {
							sprintf(traceLine,
									"***Error trying to unlock cache file read lock.\n");
							errorLog(vmapiContextP, __func__, TO_STRING(
									__LINE__), RcFunction, RsUnexpected,
									traceLine);
							return PROCESSING_ERROR;
						}

						TRACE_START(vmapiContextP, TRACEAREA_CACHE,
								TRACELEVEL_DETAILS);
						sprintf(traceLine, "Cache file read lock unlocked.\n");
						TRACE_END_DEBUG(vmapiContextP, traceLine);

					}
				}

				if (0 != fclose(cacheFileP)) {
					sprintf(traceLine, "***Error trying to close cache file.\n");
					errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
							RcFunction, RsUnexpected, traceLine);
					return PROCESSING_ERROR;
				}

				TRACE_START(vmapiContextP, TRACEAREA_CACHE, TRACELEVEL_DETAILS);
				sprintf(traceLine, "Cache file closed.\n");
				TRACE_END_DEBUG(vmapiContextP, traceLine);

				// If cache data used return to caller
				if (dataReadFromCache) {
					return rc;
				}

			}
		}
		// Cache file is invalid/missing/(out of date) remove it
		else {
			if (remove(cachePath)) {
				// If the error is anything but the file is not found
				if (ENOENT != errno) {
					sprintf(
							traceLine,
							"***Error removing out of date cache file <%.*s> errno %d\n",
							LINESIZE, cachePath, errno);
					errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
							RcFunction, RsUnexpected, traceLine);
					return PROCESSING_ERROR;
				}
				TRACE_START(vmapiContextP, TRACEAREA_CACHE, TRACELEVEL_DETAILS);
				sprintf(traceLine, "Cache file not found.\n");
				TRACE_END_DEBUG(vmapiContextP, traceLine);
			} else {
				TRACE_START(vmapiContextP, TRACEAREA_CACHE, TRACELEVEL_DETAILS);
				sprintf(traceLine, "Cache file erased, too old.\n");
				TRACE_END_DEBUG(vmapiContextP, traceLine);
			}
		}
	}

	// Build SMAPI input parameter buffer
	if (0 == (inputP = malloc(inputSize)))
		return MEMORY_ERROR;
	cursor = inputP;
	PUT_INT(inputSize - 4, cursor);

	tempSize = strlen(functionName);
	PUT_INT(tempSize, cursor);
	memcpy(cursor, functionName, tempSize);
	cursor += tempSize;

	tempSize = strlen(userid); // Userid 1..8 or 0..8 chars
	PUT_INT(tempSize, cursor);
	if (tempSize > 0) {
		memcpy(cursor, userid, tempSize);
		cursor += tempSize;
	}

	tempSize = passwordLength; // Password 1..200 or 0..200 chars
	PUT_INT(tempSize, cursor);
	if (tempSize > 0) {
		memcpy(cursor, password, tempSize);
		cursor += tempSize;
	}

	tempSize = strlen(targetIdentifier); // Target identifier 1..8
	PUT_INT(tempSize, cursor);
	memcpy(cursor, targetIdentifier, tempSize);
	cursor += tempSize;

	// This routine will send SMAPI the input, delete the input storage
	// and call the table parser to set the output in outData
	rc = getAndParseSmapiBuffer(vmapiContextP, &inputP, inputSize,
			PARSER_TABLE_NAME, // Integer table
			TO_STRING(PARSER_TABLE_NAME), // String name of the table
			(char * *) outData);

	if (0 == rc) {
		if ((0 == (*outData)->common.returnCode) && (0
				== (*outData)->common.reasonCode)) {
			// Write the cache file
			// Build path to the cache directory
			memset(cachePath, 0, sizeof(cachePath));
			vmbkendGetCachePath(vmapiContextP, cachePath);
			strcat(cachePath, "users.list");

			if (cachePath) {
				createDirectories(cachePath);
				cacheFileP = fopen(cachePath, "w");
				if (NULL == cacheFileP) {
					sprintf(
							traceLine,
							"***Error trying to open cache file for write. errno %d\n",
							errno);
					errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
							RcFunction, RsUnexpected, traceLine);
					return PROCESSING_ERROR;
				}

				TRACE_START(vmapiContextP, TRACEAREA_CACHE, TRACELEVEL_DETAILS);
				sprintf(traceLine,
						"Cache file pointer opened for WRITE: %p \n",
						cacheFileP);
				TRACE_END_DEBUG(vmapiContextP, traceLine);

				if (cacheFileP != NULL) {
					cacheFileFD = fileno(cacheFileP);

					TRACE_START(vmapiContextP, TRACEAREA_CACHE,
							TRACELEVEL_DETAILS);
					sprintf(traceLine,
							"Cache file integer descriptor value: %d \n",
							cacheFileFD);
					TRACE_END_DEBUG(vmapiContextP, traceLine);

					if (cacheFileFD != -1) {
						// Lock the file while writing, so no one else is using it
						fl.l_type = F_WRLCK;
						fl.l_whence = SEEK_SET;
						fl.l_start = 0;
						fl.l_len = 0;
						if (fcntl(cacheFileFD, F_SETLK, &fl) != -1) {

							TRACE_START(vmapiContextP, TRACEAREA_CACHE,
									TRACELEVEL_DETAILS);
							sprintf(traceLine,
									"Cache file WRITE lock obtained.\n");
							TRACE_END_DEBUG(vmapiContextP, traceLine);

							temp = (*outData)->nameCount;

							if (temp > 0) {
								for (i = 0; i < temp; i++) {
									memset(resultLine, 0, 9);
									memcpy(
											resultLine,
											(*outData)->nameList[i].imageName,
											strlen(
													(*outData)->nameList[i].imageName)
													+ 1);
									strcat(resultLine, "\n");
									fprintf(cacheFileP, "%s", resultLine);
									TRACE_START(vmapiContextP, TRACEAREA_CACHE,
											TRACELEVEL_DETAILS);
									sprintf(
											traceLine,
											"Adding user id  <%s>  in Cache \n",
											resultLine);
									TRACE_END_DEBUG(vmapiContextP, traceLine);

									rc = fflush(cacheFileP);
									if (EOF == rc) {
										// Can't write to file, try to remove file
										if (0 != fclose(cacheFileP)) {
											sprintf(traceLine,
													"***Error trying to close cache file.\n");
											errorLog(vmapiContextP, __func__,
													TO_STRING(__LINE__),
													RcFunction, RsUnexpected,
													traceLine);
											return PROCESSING_ERROR;
										}
										cacheFileP = 0;
										if (remove(cachePath)) {
											sprintf(
													traceLine,
													"***Error removing cache file after write error <%.*s> errno %d\n",
													LINESIZE, cachePath, errno);
											errorLog(vmapiContextP, __func__,
													TO_STRING(__LINE__),
													RcFunction, RsUnexpected,
													traceLine);
											return PROCESSING_ERROR;
										}
										return rc; // Continue processing even if cache file was removed
									}
								}
							}

							// Unlock the file
							fl.l_type = F_UNLCK;
							fl.l_whence = SEEK_SET;
							fl.l_start = 0;
							fl.l_len = 0;
							if (-1 == fcntl(cacheFileFD, F_SETLK, &fl)) {

								sprintf(traceLine,
										"***Error trying to unlock cache file WRITE lock.\n");
								errorLog(vmapiContextP, __func__, TO_STRING(
										__LINE__), RcFunction, RsUnexpected,
										traceLine);
								return PROCESSING_ERROR;
							}

							TRACE_START(vmapiContextP, TRACEAREA_CACHE,
									TRACELEVEL_DETAILS);
							sprintf(traceLine,
									"Cache file write lock unlocked.\n");
							TRACE_END_DEBUG(vmapiContextP, traceLine);

						}
					}

					if (0 != fclose(cacheFileP)) {
						sprintf(traceLine,
								"***Error trying to close cache file.\n");
						errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
								RcFunction, RsUnexpected, traceLine);
						return PROCESSING_ERROR;
					}
					TRACE_START(vmapiContextP, TRACEAREA_CACHE,
							TRACELEVEL_DETAILS);
					sprintf(traceLine, "Cache file closed.\n");
					TRACE_END_DEBUG(vmapiContextP, traceLine);

				}
			}
		}
	}

	return rc;
}
