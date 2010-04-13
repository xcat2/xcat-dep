// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "smSocket.h"
#include "vmapiImage.h"
#include "smapiTableParser.h"
#include <stdlib.h>
#include <string.h>
#include <netinet/in.h>

#define PARSER_TABLE_NAME     Image_Create_DM_Layout
#define OUTPUT_STRUCTURE_NAME vmApiImageCreateDmOutput

/**
 * Image_Create_DM SMAPI interface
 */
int smImage_Create_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, char * prototypeName,
		int initialPasswordLength, char * initialPassword,
		char * initialAccountNumber, int imageRecordCount,
		vmApiImageRecord * imageRecordList, vmApiImageCreateDmOutput ** outData) {
	const char * const functionName = "Image_Create_DM";
	tableParserParms parserParms;
	int tempSize;
	char * cursor;
	char * stringCursor; // Used for outData string area pointer
	int arrayCount;
	int totalStringSize;
	int rc;
	int sockDesc;
	int requestId;

	int inputSize = 4 + 4 + strlen(functionName) + 4 + strlen(userid) + 4
			+ passwordLength + 4 + strlen(targetIdentifier) + 4 + strlen(
			prototypeName) + 4 + initialPasswordLength + 4 + strlen(
			initialAccountNumber) + 4;
	char * inputP = 0;
	char * smapiOutputP = 0;
	char line[LINESIZE];
	int i;
	int imageRecordTotal = 0;
	for (i = 0; i < imageRecordCount; i++) {
		inputSize += 4; // Record length integer
		inputSize += imageRecordList[i].imageRecordLength; // Data length

		imageRecordTotal += 4;
		imageRecordTotal += imageRecordList[i].imageRecordLength;
	}

	TRACE_ENTRY_FLOW(vmapiContextP, TRACEAREA_RESOURCE_LAYER);

	// Build SMAPI input parameter buffer
	if (0 == (inputP = malloc(inputSize + 4)))
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

	tempSize = strlen(targetIdentifier); // Target identifier 1..8 (image name)
	PUT_INT(tempSize, cursor);
	memcpy(cursor, targetIdentifier, tempSize);
	cursor += tempSize;

	tempSize = strlen(prototypeName); // Prototype name 0..8
	PUT_INT(tempSize, cursor);
	if (tempSize > 0) {
		memcpy(cursor, prototypeName, tempSize);
		cursor += tempSize;
	}

	tempSize = initialPasswordLength; // Initial password 0..200
	PUT_INT(tempSize, cursor);
	if (tempSize > 0) {
		memcpy(cursor, initialPassword, tempSize);
		cursor += tempSize;
	}

	tempSize = strlen(initialAccountNumber); // Initial account number 0..8
	PUT_INT(tempSize, cursor);
	if (tempSize > 0) {
		memcpy(cursor, initialAccountNumber, tempSize);
		cursor += tempSize;
	}

	// Add in the length of images array then the data if available
	PUT_INT(imageRecordTotal, cursor);
	if (imageRecordTotal > 0) {
		for (i = 0; i < imageRecordCount; i++) {
			tempSize = imageRecordList[i].imageRecordLength; // Data length
			PUT_INT(tempSize, cursor);

			memcpy(cursor, imageRecordList[i].imageRecord, tempSize);
			cursor += tempSize;
		}
	}

	// This routine will send SMAPI the input, delete the input storage
	// and call the table parser to set the output in outData
	rc = getAndParseSmapiBuffer(vmapiContextP, &inputP, inputSize,
			PARSER_TABLE_NAME, // Integer table
			TO_STRING(PARSER_TABLE_NAME), // String name of the table
			(char * *) outData);
	return rc;
}
