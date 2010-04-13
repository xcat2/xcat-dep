// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "smapiTableParser.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "smPublic.h"
#include "smSocket.h"

// Internal function to handle imbedded arrays in smapi output
static int handleArrays(struct _VmApiInternalContext* vmapiContextP,
		enum tableParserModes mode, int * tableStartingIndex,
		tableLayout table, tableParserParms * parms);

int parseBufferWithTable(struct _VmApiInternalContext* vmapiContextP,
		enum tableParserModes mode, tableLayout table, tableParserParms *parms) {
	int temp, dataType, i, rc, iSize, reachedByteCount;
	int cStringArrayPtrOffset, cStringArrayPtrIndex;
	int cStringCounterFieldOffset, cStringCounterFieldIndex;
	int cStringStructIndex, cStringStructSize;
	int cStringFieldIndex, cStringFieldOffset, cStringCurrentStructCount;
	char line[LINESIZE];

	reachedByteCount = 0; // Set this if we are at the end of the data

	// If this is a SCAN mode; clear out the output fields
	if (mode == scan) {
		parms->outStringByteCount = 0;
		for (i = 0; i < MAX_STRUCT_ARRAYS; i++) {
			parms->outStructCount[i] = 0;
			parms->outStructSizes[i] = 0;
		}
	}

	parms->byteCount = 0;

	// First entry in the table must be the base structure size
	if (table[0][COL_1_TYPE] != APITYPE_BASE_STRUCT_LEN) {
		errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
				RsUnexpected, "Parser found a problem in the internal table\n");
		return PARSER_ERROR_INVALID_TABLE;
	}

	// If this is scan mode, fill in the output array size for top level structure
	if (mode == scan) {
		parms->outStructSizes[0] = table[0][COL_6_SIZE_OR_OFFSET];
		parms->outStructCount[0] = 1;
	}

	for (i = 1; (table[i][COL_1_TYPE] != APITYPE_END_OF_TABLE)
			&& (parms->byteCount < parms->dataBufferSize); i++) {
		dataType = table[i][COL_1_TYPE];
		switch (dataType) {
		case APITYPE_INT1:
			if (mode == populate) {
				memcpy((parms->inStructAddrs[0]
						+ table[i][COL_6_SIZE_OR_OFFSET]),
						parms->smapiBufferCursor, 1);
			}
			parms->smapiBufferCursor += 1;
			parms->byteCount += 1;
			break;

		case APITYPE_INT4:
			if (mode == populate) {
				GET_INT(*((int *) (parms->inStructAddrs[0]
						+ table[i][COL_6_SIZE_OR_OFFSET])),
						parms->smapiBufferCursor);

				TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
						TRACELEVEL_DETAILS);
				sprintf(line, "int 4 found Value %d stored at %p(+%d) \n",
						*((int *) (parms->inStructAddrs[0]
								+ table[i][COL_6_SIZE_OR_OFFSET])),
						parms->inStructAddrs[0], table[i][COL_6_SIZE_OR_OFFSET]);
				TRACE_END_DEBUG(vmapiContextP, line);

			} else
				parms->smapiBufferCursor += 4;
			parms->byteCount += 4;
			break;

		case APITYPE_INT8:
			if (mode == populate) {
				GET_64INT(*((long long*) (parms->inStructAddrs[0]
						+ table[i][COL_6_SIZE_OR_OFFSET])),
						parms->smapiBufferCursor);
			} else
				parms->smapiBufferCursor += 8;
			parms->byteCount += 8;
			break;

		case APITYPE_STRING_LEN:
		case APITYPE_CHARBUF_LEN:
		case APITYPE_C_STR_PTR:
			if (APITYPE_C_STR_PTR == dataType) {
				temp = strlen(parms->smapiBufferCursor);
				TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
						TRACELEVEL_DETAILS);
				sprintf(line, "C string found of length %d <%s>\n", temp,
						parms->smapiBufferCursor);
				TRACE_END_DEBUG(vmapiContextP, line);
				parms->byteCount += (temp + 1);
			} else {
				GET_INT(temp, parms->smapiBufferCursor);
				parms->byteCount += 4;
				parms->byteCount += temp;
			}
			// If the string size is incorrect, display error and return.
			if (temp < table[i][COL_2_MINSIZE]) // Check for less than min first
			{
				sprintf(
						line,
						"String size found: %d (@ %p), not in correct range %d-%d \n",
						temp, (parms->smapiBufferCursor - 4),
						table[i][COL_2_MINSIZE], table[i][COL_3_MAXSIZE]);
				errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
						RcRuntime, RsUnexpected, line);
				return PARSER_ERROR_INVALID_STRING_SIZE;
			}
			// If max is not -1, then check for max
			if (-1 != table[i][COL_3_MAXSIZE] && temp > table[i][COL_3_MAXSIZE]) {
				sprintf(
						line,
						"String size found: %d (@ %p), not in correct range %d-%d \n",
						temp, (parms->smapiBufferCursor - 4),
						table[i][COL_2_MINSIZE], table[i][COL_3_MAXSIZE]);
				errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
						RcRuntime, RsUnexpected, line);
				return PARSER_ERROR_INVALID_STRING_SIZE;
			}
			// If scan update the string byte count
			if (mode == scan) {
				if (temp > 0) {
					parms->outStringByteCount += (temp + 1);
				}
				if (APITYPE_CHARBUF_LEN == dataType) // Skip past the buf count row in table
				{
					i++;
					(parms->outStringByteCount)--; // Don't need null terminator for char buf
				}
			} else { // If populate then set the char * in struct; copy the string/charbuf into the buffer
				if (temp > 0) {
					*((char **) ((parms->inStructAddrs[0]
							+ table[i][COL_6_SIZE_OR_OFFSET])))
							= parms->inStringCursor;

					// If this ia a null terminated string just just strcpy, else use memcpy
					if (APITYPE_C_STR_PTR == dataType) {
						strcpy(parms->inStringCursor, parms->smapiBufferCursor);
						parms->inStringCursor += temp + 1;
					} else {
						// copy the string/charbuf into the string buffer and add zero terminator if a string
						memcpy(parms->inStringCursor, parms->smapiBufferCursor,
								temp);
						parms->inStringCursor += temp;
						if (APITYPE_STRING_LEN == dataType) {
							*(parms->inStringCursor) = '\0';
							parms->inStringCursor++;
						} else // Char buffer, so no need to add null terminator, but must update count field
						{
							i++;
							*((int*) (parms->inStructAddrs[0]
									+ table[i][COL_6_SIZE_OR_OFFSET])) = temp;
						}
					}
				} else {
					*((char**) (parms->inStructAddrs[0]
							+ table[i][COL_6_SIZE_OR_OFFSET])) = NULL;
					if (APITYPE_CHARBUF_LEN == dataType) // Set char buf count to 0
					{
						i++;
						*((int*) (parms->inStructAddrs[0]
								+ table[i][COL_6_SIZE_OR_OFFSET])) = 0;
					}
				}
			}
			if (APITYPE_C_STR_PTR == dataType) {
				temp++; // Add on a byte for zero terminator
			}
			parms->smapiBufferCursor += temp;
			break;

		case APITYPE_ARRAY_LEN:
			// Call a subroutine to handle this
			if (0 != (rc = handleArrays(vmapiContextP, mode, &i, table, parms)))
				return rc;
			TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
					TRACELEVEL_DETAILS);
			sprintf(
					line,
					"** Finished handling an array in parseBufferwithTable. Buffer pointer %p \n",
					parms->smapiBufferCursor);
			TRACE_END_DEBUG(vmapiContextP, line);

			break;

			// If null terminated strings are in the base structure, we need to
			// find them all until we use up the buffer. They must be the last
			// type of data in the stream.
			// For scan mode we need to add up all the string lengths (adding in a byte
			// for the null terminator) until the buffer is empty.
			// The static table will have the APITYPE_C_STR_ARRAY_PTR, then APITYPE_C_STR_ARRAY_COUNT,
			// APITYPE_C_STR_STRUCT_LEN, APITYPE_C_STR_PTR in that order.
		case APITYPE_C_STR_ARRAY_PTR:

			cStringArrayPtrOffset = table[i][COL_6_SIZE_OR_OFFSET]; // Get the offset where the array ptr will be stored
			cStringArrayPtrIndex = table[i][COL_4_STRUCT_INDEX];// Get the index of this field (should be 0 for this level)

			i++; // Get next table value; which must be the counter info
			if (APITYPE_C_STR_ARRAY_COUNT != table[i][COL_1_TYPE]) {
				errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
						RcRuntime, RsUnexpected,
						"Parser found a problem in the internal table\n");
				return PARSER_ERROR_INVALID_TABLE;
			}
			cStringCounterFieldOffset = table[i][COL_6_SIZE_OR_OFFSET];
			cStringCounterFieldIndex = table[i][COL_4_STRUCT_INDEX];

			i++; // Get next table value; which must be the c array structure size info
			if (APITYPE_C_STR_STRUCT_LEN != table[i][COL_1_TYPE]) {
				errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
						RcRuntime, RsUnexpected,
						"Parser found a problem in the internal table\n");
				return PARSER_ERROR_INVALID_TABLE;
			}
			cStringStructSize = table[i][COL_6_SIZE_OR_OFFSET];
			cStringStructIndex = table[i][COL_4_STRUCT_INDEX];

			i++; // Get next table value; which must be the char * offset in the structure
			if (APITYPE_C_STR_PTR != table[i][COL_1_TYPE]) {
				errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
						RcRuntime, RsUnexpected,
						"Parser found a problem in the internal table\n");
				return PARSER_ERROR_INVALID_TABLE;
			}
			cStringFieldIndex = table[i][COL_4_STRUCT_INDEX];
			cStringFieldOffset = table[i][COL_6_SIZE_OR_OFFSET];

			cStringCurrentStructCount = 0; // Used in populate

			// Look through the rest of the buffer.
			while (parms->byteCount < parms->dataBufferSize) {
				iSize = strlen(parms->smapiBufferCursor) + 1;
				// If this is scan, then increment the c string structure count,
				// add the output size of the string + byte for zero terminator, and
				// move buffer pointer past the string. Increment our count of data bytes
				// processed also.
				if (mode == scan) {
					parms->outStringByteCount += iSize;
					parms->smapiBufferCursor += iSize;
					parms->outStructCount[cStringStructIndex]++;// Structures hold the char *

					// If the size of the char * structure has not been filled in, do that now
					if (0 == parms->outStructSizes[cStringStructIndex]) {
						parms->outStructSizes[cStringStructIndex]
								= cStringStructSize;
					}
				}
				// If populate, copy the string to the storage area,
				// store the pointer to the string in the correct array structure,
				// then move to next string.
				else {
					// If this is the first string/structure, then set the structure pointer to to the
					// starting address. The array notation will handle the rest of the addresses.
					if (0 == cStringCurrentStructCount) {
						*(char **) (parms->inStructAddrs[cStringArrayPtrIndex]
								+ cStringArrayPtrOffset)
								= parms->inStructAddrs[cStringStructIndex];

						// Copy the struct count from the scan (input to this populate) into the
						// count field
						*((int *) (parms->inStructAddrs[cStringCounterFieldIndex]
								+ cStringCounterFieldOffset))
								= parms->outStructCount[cStringStructIndex];
					}

					// Copy the string into the string buffer
					strcpy(parms->inStringCursor, parms->smapiBufferCursor);

					// Set the char * pointer in the c structure of char *'s
					memcpy((parms->inStructAddrs[cStringStructIndex]
							+ (cStringCurrentStructCount * cStringStructSize)
							+ cStringFieldOffset), &(parms->inStringCursor),
							sizeof(char *));

					// Advance to next string storage location and structure counter
					parms->inStringCursor += iSize;
					parms->smapiBufferCursor += iSize;

					cStringCurrentStructCount++;
				}
				parms->byteCount += iSize;
			}// End while buffer has data

			break;

		case APITYPE_ARRAY_STRUCT_COUNT: // Should not get here, subroutine should be handling this
			errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
					RsUnexpected,
					"Parser found a problem in the internal table\n");
			return PARSER_ERROR_INVALID_TABLE;
			break;

		default: // Error
			errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
					RsUnexpected,
					"Parser found a problem in the internal table\n");
			return PARSER_ERROR_INVALID_TABLE;
			break;
		}// End switch on table type

		if (parms->byteCount >= parms->dataBufferSize) {
			reachedByteCount = 1;
			break; // End of for loop (Will we always get here vs find the last entry in the table?)
		}
	}// For loop until end of table
	return 0;
}

/**
 * Routine for doing all processing when an array is found.
 * Can be recursively called if nested arrays
 */
static int handleArrays(struct _VmApiInternalContext* vmapiContextP,
		enum tableParserModes mode, int * tableStartingIndex,
		tableLayout table, tableParserParms *parms) {
	// At our calling the table index should be at the arrayLen field, and next field should be
	// struct len details.
	int arrayByteMax, arrayByteCount, arrayPointerOffset, arrayPointerIndex, j,
			dataType;
	int dataBuffStructSize, outStructSize, structIndex, structByteCount;
	int tableIndex, tableMaxIndex, temp, rc, arrayNestLevel;
	int structCounter, structCounterField, structCounterIndex;
	int noBufferStructLen; // set to 1 if SMAPI array doesn't have an inner structure length
	char * structStorage;
	char line[LINESIZE];

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
			TRACELEVEL_DETAILS);
	sprintf(line,
			"** Array found. Starting table index is %d buffer pointer %p \n",
			*tableStartingIndex, parms->smapiBufferCursor);
	TRACE_END_DEBUG(vmapiContextP, line);

	arrayByteCount = 0;
	tableMaxIndex = 0; // Used to find end of table entries for this structure
	structCounter = 0; // Used for populate of structure (an address multiplier)

	GET_INT(arrayByteMax, parms->smapiBufferCursor);// Actual size of SMAPI array data

	arrayPointerOffset = table[*tableStartingIndex][COL_6_SIZE_OR_OFFSET];
	arrayPointerIndex = table[*tableStartingIndex][COL_4_STRUCT_INDEX];
	arrayNestLevel = table[*tableStartingIndex][COL_5_NEST_LEVEL];
	(*tableStartingIndex)++; // Position at the struct len in this table (or struct count)

	// If the struct count field was specified, then make a note of that for populate step
	if (APITYPE_ARRAY_STRUCT_COUNT == table[*tableStartingIndex][COL_1_TYPE]) {
		if (mode == populate) {
			structCounterField
					= table[*tableStartingIndex][COL_6_SIZE_OR_OFFSET];
			structCounterIndex = table[*tableStartingIndex][COL_4_STRUCT_INDEX];
		} else {
			structCounterField = 0;
			structCounterIndex = 0;
		}
		(*tableStartingIndex)++; // Position at the struct length APITYPE_STRUCT_LEN
	}

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
			TRACELEVEL_DETAILS);
	sprintf(line, "SMAPI buffer array found: %d bytes \n", arrayByteMax);
	TRACE_END_DEBUG(vmapiContextP, line);

	structIndex = table[*tableStartingIndex][COL_4_STRUCT_INDEX];
	outStructSize = table[*tableStartingIndex][COL_6_SIZE_OR_OFFSET];
	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
			TRACELEVEL_DETAILS);
	sprintf(line, "  Output struct size is %d \n", outStructSize);
	TRACE_END_DEBUG(vmapiContextP, line);

	// Figure out where is the ending index of the structure. This will be used in case the
	// array is empty or the size of the structure is larger than we expect. (The actual
	// structure could be bigger if the next release of SMAPI adds more fields at the end.)
	tableMaxIndex = *tableStartingIndex;
	while (arrayNestLevel < table[tableMaxIndex + 1][COL_5_NEST_LEVEL]
			&& APITYPE_END_OF_TABLE != table[tableMaxIndex + 1][COL_1_TYPE]) {
		tableMaxIndex++;
	}

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
			TRACELEVEL_DETAILS);
	sprintf(line, "  Structure's table max index is %d \n", tableMaxIndex);
	TRACE_END_DEBUG(vmapiContextP, line);

	// Find each structure until we reach array max
	while (arrayByteCount < arrayByteMax) {
		TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
				TRACELEVEL_DETAILS);
		sprintf(line, "  Loop to scan buffer for structure data. \n");
		TRACE_END_DEBUG(vmapiContextP, line);
		noBufferStructLen = 0;
		tableIndex = *tableStartingIndex;
		// Start at the field past the array in the table
		// next table field should be the array structure size or if no nested inner structure
		// the NOBUFFER keyword
		if ((APITYPE_STRUCT_LEN != table[tableIndex][COL_1_TYPE])
				&& (APITYPE_NOBUFFER_STRUCT_LEN
						!= table[tableIndex][COL_1_TYPE])) {
			printf("table index %d column1 type: %d \n", tableIndex,
					table[tableIndex][COL_1_TYPE]);
			errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
					RsUnexpected,
					"Parser found a problem in the internal table\n");
			return PARSER_ERROR_INVALID_TABLE;
		}
		structByteCount = 0;

		GET_INT(dataBuffStructSize, parms->smapiBufferCursor);
		// If the SMAPI buffer does not contain a nested structure size, then set
		// the data pointer back to make the "implied" structure.
		if (APITYPE_NOBUFFER_STRUCT_LEN == table[tableIndex][COL_1_TYPE]) {
			TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
					TRACELEVEL_DETAILS);
			sprintf(
					line,
					"  There is no inner structure length, so this length %d is first item, back up to re-read it later. \n",
					dataBuffStructSize);
			TRACE_END_DEBUG(vmapiContextP, line);
			parms->smapiBufferCursor -= 4;
			noBufferStructLen = 1; // set flag so that correct count at bottom of loop is done
		}

		if (mode == scan) {
			parms->outStructCount[structIndex]++;
			// If the size of the structure has not been filled in, do that now
			if (0 == parms->outStructSizes[structIndex]) {
				parms->outStructSizes[structIndex]
						= table[tableIndex][COL_6_SIZE_OR_OFFSET];
			}
		} else { // If populate and structCounterField specified, then fill it in
			if (0 == structCounter) {
				*(char **) (parms->inStructAddrs[arrayPointerIndex]
						+ arrayPointerOffset)
						= parms->inStructAddrs[structIndex];
			}
			if (structCounterField) {
				*((int *) (parms->inStructAddrs[structCounterIndex]
						+ structCounterField))
						= parms->outStructCount[structIndex];
			}
		}
		TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
				TRACELEVEL_DETAILS);
		if (noBufferStructLen == 1) {
			sprintf(
					line,
					" table index %d implied Array struct index %d first data item size %d\n",
					tableIndex, structIndex, dataBuffStructSize);
		} else {
			sprintf(line,
					" table index %d Array struct index %d data size %d\n",
					tableIndex, structIndex, dataBuffStructSize);
		}
		TRACE_END_DEBUG(vmapiContextP, line);
		if (dataBuffStructSize == 0)
			continue; // Probably rare?


		tableIndex++;
		// Loop until reaching the end of the table or if an imbedded structure size,
		// When the data has been all read.
		while ((noBufferStructLen == 0
				&& (structByteCount < dataBuffStructSize))
				|| (noBufferStructLen && (tableIndex <= tableMaxIndex))) {
			TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
					TRACELEVEL_DETAILS);
			sprintf(
					line,
					" noBufferStructLen %d structByteCount %d table index %d \n",
					noBufferStructLen, structByteCount, tableIndex);
			TRACE_END_DEBUG(vmapiContextP, line);

			// If we are at the end of this table, then adjust the byte count and leave
			// this loop. This would happen if there is more data than we expect. (A newer
			// version of SMAPI may of added more fields at the end.
			if (tableIndex > tableMaxIndex) {
				TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
						TRACELEVEL_DETAILS);
				sprintf(
						line,
						" Reached the end of the table. Unexpected condition. Table index %d \n",
						tableIndex);
				TRACE_END_DEBUG(vmapiContextP, line);
				structByteCount = dataBuffStructSize;
				break;
			}

			dataType = table[tableIndex][0];
			switch (dataType) {
			case APITYPE_INT1:
				TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
						TRACELEVEL_DETAILS);
				sprintf(line, " Int1 found.\n");
				TRACE_END_DEBUG(vmapiContextP, line);
				if (mode == populate) {
					memcpy((parms->inStructAddrs[structIndex] + (structCounter
							* outStructSize)
							+ table[tableIndex][COL_6_SIZE_OR_OFFSET]),
							parms->smapiBufferCursor, 1);
				}
				parms->smapiBufferCursor += 1;
				structByteCount += 1;
				break;

			case APITYPE_INT4:
				TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
						TRACELEVEL_DETAILS);
				sprintf(line, " Int4 found.\n");
				TRACE_END_DEBUG(vmapiContextP, line);
				if (mode == populate) {
					GET_INT(*((int*) (parms->inStructAddrs[structIndex]
							+ (structCounter * outStructSize)
							+ table[tableIndex][COL_6_SIZE_OR_OFFSET])),
							parms->smapiBufferCursor);
					TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
							TRACELEVEL_DETAILS);
					sprintf(
							line,
							"int 4 found Value %d stored at %p(+%d) \n",
							*((int *) (parms->inStructAddrs[structIndex]
									+ (structCounter * outStructSize)
									+ table[tableIndex][COL_6_SIZE_OR_OFFSET])),
							parms->inStructAddrs[structIndex],
							table[tableIndex][COL_6_SIZE_OR_OFFSET]);
					TRACE_END_DEBUG(vmapiContextP, line);
				} else
					parms->smapiBufferCursor += 4;

				structByteCount += 4;
				break;

			case APITYPE_INT8:
				TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
						TRACELEVEL_DETAILS);
				sprintf(line, " Int8 found.\n");
				TRACE_END_DEBUG(vmapiContextP, line);
				if (mode == populate) {
					GET_64INT(*((long long*) (parms->inStructAddrs[structIndex]
							+ (structCounter * outStructSize)
							+ table[tableIndex][COL_6_SIZE_OR_OFFSET])),
							parms->smapiBufferCursor);
				} else
					parms->smapiBufferCursor += 8;
				structByteCount += 8;
				break;

			case APITYPE_STRING_LEN:
			case APITYPE_CHARBUF_LEN:
			case APITYPE_C_STR_PTR:
				if (APITYPE_C_STR_PTR == dataType) {
					temp = strlen(parms->smapiBufferCursor);
					TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
							TRACELEVEL_DETAILS);
					sprintf(line, " C string found. Length %d\n", temp);
					TRACE_END_DEBUG(vmapiContextP, line);
				} else {
					GET_INT(temp, parms->smapiBufferCursor);
					structByteCount += 4;
					TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
							TRACELEVEL_DETAILS);
					if (dataType == APITYPE_CHARBUF_LEN) {
						sprintf(line, " Charbuf with length %d found.\n", temp);
					} else {
						sprintf(line, " String with length %d found.\n", temp);
					}
					TRACE_END_DEBUG(vmapiContextP, line);
				}

				// If the string size is incorrect, display error and return.
				if (temp < table[tableIndex][COL_2_MINSIZE]) // Check for less than min first
				{
					sprintf(
							line,
							"String size found: %d (@ %p), not in correct range %d-%d \n",
							temp, (parms->smapiBufferCursor - 4),
							table[tableIndex][COL_2_MINSIZE],
							table[tableIndex][COL_3_MAXSIZE]);
					errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
							RcRuntime, RsUnexpected, line);
					return PARSER_ERROR_INVALID_STRING_SIZE;
				}
				// If max is not -1, then check for max
				if (-1 != table[tableIndex][COL_3_MAXSIZE] && temp
						> table[tableIndex][COL_3_MAXSIZE]) {
					sprintf(
							line,
							"String size found: %d (@ %p), not in correct range %d-%d \n",
							temp, (parms->smapiBufferCursor - 4),
							table[tableIndex][COL_2_MINSIZE],
							table[tableIndex][COL_3_MAXSIZE]);
					errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
							RcRuntime, RsUnexpected, line);
					return PARSER_ERROR_INVALID_STRING_SIZE;
				}

				// If scan update the string byte count
				if (mode == scan) {
					if (temp > 0) {
						parms->outStringByteCount += (temp + 1);
					}
					if (dataType == APITYPE_CHARBUF_LEN) {
						tableIndex++; // Position at the char buf count in the table
					}
				} else { // If populate then set the char * in struct; copy the string into the buffer
					if (temp > 0) {
						*((char **) ((parms->inStructAddrs[structIndex]
								+ (structCounter * outStructSize)
								+ table[tableIndex][COL_6_SIZE_OR_OFFSET])))
								= parms->inStringCursor;

						// If this ia a null terminated string just just strcpy, else use memcpy
						if (APITYPE_C_STR_PTR == dataType) {
							strcpy(parms->inStringCursor,
									parms->smapiBufferCursor);
							parms->inStringCursor += temp + 1;
						} else {
							// Copy the string into the string buffer and add zero terminator
							TRACE_START(vmapiContextP,
									TRACEAREA_RESOURCE_LAYER_PARSER,
									TRACELEVEL_DETAILS);
							sprintf(
									line,
									"Memcopying string data from %p into %p for length %d \n",
									parms->smapiBufferCursor,
									parms->inStringCursor, temp);
							TRACE_END_DEBUG(vmapiContextP, line);
							memcpy(parms->inStringCursor,
									parms->smapiBufferCursor, temp);
							parms->inStringCursor += temp;

							if (APITYPE_STRING_LEN == dataType) {
								*parms->inStringCursor = '\0';
								parms->inStringCursor++;
								TRACE_START(vmapiContextP,
										TRACEAREA_RESOURCE_LAYER_PARSER,
										TRACELEVEL_DETAILS);
								sprintf(
										line,
										"String found Value '%s' next avail struct pointer %p \n",
										*((char**) (parms->inStructAddrs[structIndex]
												+ (structCounter
														* outStructSize)
												+ +table[tableIndex][COL_6_SIZE_OR_OFFSET])),
										parms->inStringCursor);
								TRACE_END_DEBUG(vmapiContextP, line);
							} else // Char buffer, so no need to add null terminator, but must update count field
							{
								tableIndex++; // Position at the char buf count in the table
								*((int*) (parms->inStructAddrs[structIndex]
										+ (structCounter * outStructSize)
										+ table[tableIndex][COL_6_SIZE_OR_OFFSET]))
										= temp;
								TRACE_START(vmapiContextP,
										TRACEAREA_RESOURCE_LAYER_PARSER,
										TRACELEVEL_DETAILS);
								sprintf(
										line,
										"Charbuf count at table index %d updated \n",
										tableIndex);
								TRACE_END_DEBUG(vmapiContextP, line);
							}
						}
					} else {
						*((char**) (parms->inStructAddrs[structIndex]
								+ (structCounter * outStructSize)
								+ table[tableIndex][COL_6_SIZE_OR_OFFSET]))
								= NULL;
					}
				}
				if (APITYPE_C_STR_PTR == dataType) {
					temp++; // Add on a byte for zero terminator
				}
				parms->smapiBufferCursor += temp;
				structByteCount += temp;
				break;

			case APITYPE_ARRAY_LEN:
				TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
						TRACELEVEL_DETAILS);
				sprintf(line, " Array found.\n");
				TRACE_END_DEBUG(vmapiContextP, line);
				// Call a subroutine to handle this
				if (0 != (rc = handleArrays(vmapiContextP, mode, &tableIndex,
						table, parms)))
					return rc;

				break;

			case APITYPE_ARRAY_STRUCT_COUNT: // Should not get here, subroutine should be handling this
				errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
						RcRuntime, RsUnexpected,
						"Parser found a problem in the internal table\n");
				return PARSER_ERROR_INVALID_TABLE;
				break;

			default: // Error
				errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
						RcRuntime, RsUnexpected,
						"Parser found a problem in the internal table\n");
				return PARSER_ERROR_INVALID_TABLE;
				break;
			}
			tableIndex++;
		}
		structCounter++;

		if (noBufferStructLen) {
			arrayByteCount += structByteCount;
		} else {
			arrayByteCount += structByteCount + 4; // Add in struct len field also
		}

		TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
				TRACELEVEL_DETAILS);
		sprintf(line, " current arrayByteCount subtotal is %d \n",
				arrayByteCount);
		TRACE_END_DEBUG(vmapiContextP, line);
	}
	*tableStartingIndex = tableMaxIndex;
	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
			TRACELEVEL_DETAILS);
	sprintf(line, "table starting Index on return is %d \n",
			*tableStartingIndex);
	TRACE_END_DEBUG(vmapiContextP, line);
	return 0;
}

/**
 * This helper function will handle connecting and reading of the SMAPI buffer data.
 */
int getAndParseSmapiBuffer(
		struct _VmApiInternalContext* vmapiContextP,
		char * * inputPp, // input buffer pointer pointer
		int inputSize, tableLayout parserTable, char * parserTableName,
		char * * outData //Output pointer for base structure
) {
	int sockDesc;
	tableParserParms parserParms;
	int requestId;
	int tempSize;
	int * pReturnCode;
	int * pReasonCode;
	int rc, i, j;
	char line[BUFLEN];
	char * smapiOutputP = 0;
	rc = 0;
	const int SLEEP_TIMES[SEND_RETRY_LIMIT] = { 0, 8, 16, 16 };

	TRACE_START(vmapiContextP, TRACEAREA_RESOURCE_LAYER_PARSER,
			TRACELEVEL_DETAILS);
	sprintf(line, "Table being parsed: <%s> \n", parserTableName);
	TRACE_END_DEBUG(vmapiContextP, line);

	// Initialize our socket
	if (0 != (rc = smSocketInitialize(vmapiContextP, &sockDesc))) {
		FREE_MEMORY(*inputPp);
		return rc;
	}
	TRACE_START(vmapiContextP, TRACEAREA_SMAPI_ONLY, TRACELEVEL_DETAILS);
	sprintf(line, "Socket write starting for <%s> \n", parserTableName);
	TRACE_END_DEBUG(vmapiContextP, line);

	// Retry the send if the error detected is ok to retry
	for (j = 0;; j++) {
		if (0 != (rc = smSocketWrite(vmapiContextP, sockDesc, *inputPp,
				inputSize))) {
			if (rc == SOCKET_WRITE_RETRYABLE_ERROR) {
				if (j < SEND_RETRY_LIMIT) {
					// Delay for a while to give SMAPI some time to restart
					if (SLEEP_TIMES[j] > 0) {
						sleep(SLEEP_TIMES[j]);
					}
					continue;
				}
				// Change the internal return code to general write one
				rc = SOCKET_WRITE_ERROR;
			}
			FREE_MEMORY(*inputPp);
			TRACE_START(vmapiContextP, TRACEAREA_SMAPI_ONLY, TRACELEVEL_DETAILS);
			sprintf(
					line,
					"Socket write for <%s> did not complete after %d retries \n",
					parserTableName, SEND_RETRY_LIMIT);
			TRACE_END_DEBUG(vmapiContextP, line);
			return rc;
		}
		break;
	}

	FREE_MEMORY(*inputPp);

	// Get the request id
	if (0
			!= (rc = smSocketRead(vmapiContextP, sockDesc, (char*) &requestId,
					4))) {
		sprintf(line, "Socket %d receive of the requestId failed\n", sockDesc);
		errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcIucv,
				RsUnexpected, line);
		return rc;
	}

	// Read in the output length
	if (0
			!= (rc = smSocketRead(vmapiContextP, sockDesc, (char *) &tempSize,
					4))) {
		sprintf(line, "Socket %d receive of the buffer length failed\n",
				sockDesc);
		errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcIucv,
				RsUnexpected, line);
		return rc;
	}
	tempSize = ntohl(tempSize);

	// Read in the rest of the output buffer
	if (tempSize >= (3* 4 )) // Must have at least  3 more ints
	{
		if (0 == (smapiOutputP = malloc(tempSize))) {
			sprintf(line, "Insufficiant memory (request=%d bytes)\n", tempSize);
			errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
					RsNoMemory, line);
			return MEMORY_ERROR;
		}

		if (0 != (rc = smSocketRead(vmapiContextP, sockDesc, smapiOutputP,
				tempSize))) {
			FREE_MEMORY(smapiOutputP);
			return rc;
		}

		if (0 != (rc = smSocketTerminate(vmapiContextP, sockDesc))) {
			FREE_MEMORY(smapiOutputP);
			return rc;
		}

		TRACE_START(vmapiContextP, TRACEAREA_SMAPI_ONLY, TRACELEVEL_DETAILS);
		pReturnCode = (int *) (smapiOutputP + 4);
		pReasonCode = (int *) (smapiOutputP + 8);
		sprintf(line, "SMAPI return code %d reason code %d \n", *pReturnCode,
				*pReasonCode);
		TRACE_END_DEBUG(vmapiContextP, line);

		// Scan the SMAPI output data to get sizes of structures and strings.
		// A non zero return code indicates errors.
		parserParms.smapiBufferCursor = smapiOutputP;
		parserParms.dataBufferSize = tempSize;

		rc = parseBufferWithTable(vmapiContextP, scan, parserTable,
				&parserParms);
		if (rc != 0) {
			// If we have an error because of invalid string size, dump out the
			// buffer to help with diagnosis. Limit the dump to 5000 characters
			if (rc == PARSER_ERROR_INVALID_STRING_SIZE) {
				if (tempSize > 5000) {
					dumpArea(vmapiContextP, smapiOutputP, 5000);
				} else {
					dumpArea(vmapiContextP, smapiOutputP, tempSize);
				}

			}
			FREE_MEMORY(smapiOutputP);
			return rc;
		}

		// We can add up all the storage or get each structure independently, do independent for now
		for (i = 0; i < MAX_STRUCT_ARRAYS; i++) {
			if (parserParms.outStructSizes[i] == 0
					|| parserParms.outStructCount[i] == 0)
				continue;
			parserParms.inStructAddrs[i] = smMemoryGroupAlloc(vmapiContextP,
					parserParms.outStructSizes[i]
							* parserParms.outStructCount[i]);
			if (parserParms.inStructAddrs[i] == 0) {
				FREE_MEMORY(smapiOutputP);
				sprintf(line, "Insufficiant memory (request=%d bytes)\n",
						parserParms.outStructSizes[i]
								* parserParms.outStructCount[i]);
				errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
						RcRuntime, RsNoMemory, line);
				return MEMORY_ERROR;
			}
		}

		// If any string data, just get one chunk of storage for that
		if (parserParms.outStringByteCount > 0) {
			parserParms.inStringCursor = smMemoryGroupAlloc(vmapiContextP,
					parserParms.outStringByteCount);
			if (parserParms.inStringCursor == 0) {
				FREE_MEMORY(smapiOutputP);
				sprintf(line, "Insufficiant memory (request=%d bytes)\n",
						parserParms.outStringByteCount);
				errorLog(vmapiContextP, __func__, TO_STRING(__LINE__),
						RcRuntime, RsNoMemory, line);
				return MEMORY_ERROR;
			}
		}

		// Set the output pointer to the level 0 structure's storage
		*outData = parserParms.inStructAddrs[0];

		parserParms.smapiBufferCursor = smapiOutputP; // reset the output cursor pointer

		rc = parseBufferWithTable(vmapiContextP, populate, parserTable,
				&parserParms);
		if (rc != 0) {
			FREE_MEMORY(smapiOutputP);
			return rc;
		}

	} else {
		sprintf(line, "Insufficiant memory (request=%d bytes)/n",
				parserParms.outStringByteCount);
		errorLog(vmapiContextP, __func__, TO_STRING(__LINE__), RcRuntime,
				RsUnexpected, line);
		return INVALID_DATA; // Not enough data returned
	}
	FREE_MEMORY(smapiOutputP);
	return 0;
}
