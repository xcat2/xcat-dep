// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _VMAPI_PARSER_ROUTINE_H
#define _VMAPI_PARSER_ROUTINE_H

#include <stddef.h>
#include <sys/types.h>
#include <netinet/in.h>
#include "smPublic.h"

#ifdef __cplusplus
extern "C" {
#endif

// This structure typedef is used for the common information returned by
// the SMAPI
typedef struct _commonOutputFields {
	int requestId;
	int returnCode;
	int reasonCode;
} commonOutputFields;

// This structure is used to handle unknown number of zero terminated data
// returned by the SMAPI. Array notation can be used to subscript the strings.
typedef struct _vmApiCStringInfo {
	char * vmapiString;
} vmApiCStringInfo;

/**
 * Parser table general layout:
 * Columns are: Type, min, max, output structure unique index number, nesting level,
 * 				offset in output structure (or size of output structure)
 *
 * 				Min and max only apply to string length items, and arrays
 *
 * NOTE:
 * Each type has the following requirements:
 *
 * APITYPE_BASE_STRUCT_LEN	Column 4 must be STRUCT_INDX_0, column 6 is size of structure
 * APITYPE_INTn  			Column 4 must have the structure index, column 6 contains the offset to store this value into
 * APITYPE_STRING_LEN	 	Column 2 must have the minimum string length, column 3 must have the maximum length or -1 if no max
 *                        	Column 4 must have the structure index, column 6 contains the offset to store this string into
 *    						If a single zero terminated string is returned in the buffer; then use
 * APITYPE_C_STR_PTR		Column 2 must have the minimum string length, column 3 must have the maximum length or -1 if no max
 *                          Column 4 must have the structure index, column 6 contains the offset to store this string into
 *
 * APITYPE_CHARBUF_LEN		Column 2 must have the minimum charaters length, column 3 must have the maximum length or -1 if no max
 *                          Column 4 must have the structure index, column 6 contains the offset to store this charater buffer pointer into
 * APITYPE_CHARBUF_COUNT	Column 4 must have the structure index, column 6 contains the offset to store the count into
 *    (CHARBUF_LEN must have a ..COUNT as the next table entry)
 *
 * APITYPE_ARRAY_LEN		Column 4 must have the structure index, column 6 contains the offset to
 *                         	store the pointer to first array element at.
 * APITYPE_ARRAY_STRUCT_COUNT 	Column 4 must have the structure index, column 6 contains the offset to store the count into
 * APITYPE_STRUCT_LEN or APITYPE_NOBUFFER_STRUCT_LEN
 * 							Column 5 must have the size of the output structure
 *    						(ARRAY must have STRUCT following; STRUCT_COUNT must have a ..LEN as the next table entry)
 *    						APITYPE_NOBUFFER_STRUCT_LEN is used when the SMAPI buffer does not have a structure size
 *    						after the array size in the returned data. (The data is an array of strings vs array of structures)
 *
 *    						When the SMAPI buffer has many zero terminated strings as output: (use the next 4 types in that order)
 *    						The vmApiCStringInfo structure can be used to hold each string.
 * APITYPE_C_STR_ARRAY_PTR	Column 4 must have the parent structure index, column 6 contains
 *                          the offset to store the pointer to first string in the array at.
 * APITYPE_C_STR_ARRAY_COUNT	Column 4 must have the structure index which hold the count field, column 6 contains the offset to store the count into
 * APITYPE_C_STR_STRUCT_LEN		Column 5 must have the size of the output structure (vmApiCStringInfo)
 * APITYPE_C_STR_PTR			Column 5 must have the offset in the C string structure of the char *
 *
 * APITYPE_END_OF_TABLE 		Must be used to end the table
 *
 * Note: use CHARBUF for strings that can contain nulls (CHARNA in zVM API data types)
 *
 * Ex:
 * static tableLayout Imalge_Activate_Layout =
 * 	{
 * {APITYPE_BASE_STRUCT_LEN,   4,4,STRUCT_INDX_0,NEST_LEVEL_0,sizeof(VmApiImageActivateOutput)                    },
 * {APITYPE_INT4,              4,4,STRUCT_INDX_0,NEST_LEVEL_0,offsetof(VmApiImageActivateOutput,common.requestId) },
 * {APITYPE_INT4,              4,4,STRUCT_INDX_0,NEST_LEVEL_0,offsetof(VmApiImageActivateOutput,common.returnCode)},
 * {APITYPE_INT4,              4,4,STRUCT_INDX_0,NEST_LEVEL_0,offsetof(VmApiImageActivateOutput,common.reasonCode)},
 * {APITYPE_INT4,              4,4,STRUCT_INDX_0,NEST_LEVEL_0,offsetof(VmApiImageActivateOutput,activated)        },
 * {APITYPE_INT4,              4,4,STRUCT_INDX_0,NEST_LEVEL_0,offsetof(VmApiImageActivateOutput,notActivated)     },
 *
 * {APITYPE_ARRAY_LEN,         4,4,STRUCT_INDX_0,NEST_LEVEL_0,offsetof(VmApiImageActivateOutput,failList)         },
 * {APITYPE_ARRAY_STRUCT_COUNT,4,4,STRUCT_INDX_0,NEST_LEVEL_0,offsetof(VmApiImageActivateOutput,failingArrayCount)},
 * {APITYPE_STRUCT_LEN,        4,4,STRUCT_INDX_1,NEST_LEVEL_1,sizeof(VmApiImageFailing)                           },
 * {APITYPE_STRING_LEN,        1,8,STRUCT_INDX_1,NEST_LEVEL_1,offsetof(VmApiImageFailing,imageName)               },
 * {APITYPE_INT4,              4,4,STRUCT_INDX_1,NEST_LEVEL_1,offsetof(VmApiImageFailing,returnCode)              },
 * {APITYPE_INT4,              4,4,STRUCT_INDX_1,NEST_LEVEL_1,offsetof(VmApiImageFailing,reasonCode)              },
 * {APITYPE_END_OF_TABLE,0,0,0,0}
 *	};
 */
#define APITYPE_END_OF_TABLE 0
#define APITYPE_INT1         1
#define APITYPE_INT4         2
#define APITYPE_INT8         3

#define APITYPE_STRING_LEN          20
#define APITYPE_ARRAY_LEN           21
#define APITYPE_ARRAY_STRUCT_COUNT  22
#define APITYPE_STRUCT_LEN          23
#define APITYPE_NOBUFFER_STRUCT_LEN 24
#define APITYPE_CHARBUF_LEN         25
#define APITYPE_CHARBUF_COUNT       26
#define APITYPE_C_STR_ARRAY_PTR     30
#define APITYPE_C_STR_ARRAY_COUNT   31
#define APITYPE_C_STR_STRUCT_LEN    32
#define APITYPE_C_STR_PTR           33
#define APITYPE_BASE_STRUCT_LEN     98

#define STRUCT_INDX_0    0
#define STRUCT_INDX_1    1
#define STRUCT_INDX_2    2
#define STRUCT_INDX_3    3
#define STRUCT_INDX_4    4
#define STRUCT_INDX_5    5
#define STRUCT_INDX_6    6
#define STRUCT_INDX_7    7
#define STRUCT_INDX_8    8
#define STRUCT_INDX_9    9
#define STRUCT_INDX_10   10

#define NEST_LEVEL_0  0
#define NEST_LEVEL_1  1
#define NEST_LEVEL_2  2
#define NEST_LEVEL_3  3

#define MAX_STRUCT_ARRAYS 10

#define COL_1_TYPE           0
#define COL_2_MINSIZE        1
#define COL_3_MAXSIZE        2
#define COL_4_STRUCT_INDEX   3
#define COL_5_NEST_LEVEL     4
#define COL_6_SIZE_OR_OFFSET 5

enum tableParserModes {
	scan, populate
};

typedef int tableLayout[][6];

/**
 * Input/output structure for use by smapiTableParser parseBufferWithTable()
 *
 * - smapiBufferCursor must be set to the start of the SMAPI data
 * - dataBufferSize must be set to the total size of the SMAPI data
 * - byteCount is used by parseBufferWithTable as a work variable
 * - outStringByteCount will be set in "scan" mode to the number of bytes needed for all the
 * strings found in the SMAPI data
 * - outStructCount array will be set in "scan" mode to the number of structures found at each
 * level
 * - outStructSizes array will be set in "scan" mode to the size of 1 structure
 * - inStructAddrs array must be set in "populate" mode to the starting address of the first
 * structure at each level
 * - inStringCursor must be set in "populate" mode to the start of the storage block for use in
 * string allocation.
 */
typedef struct _tableParserParms {
	char * smapiBufferCursor; // Input for SCAN and POPULATE. Initially set to output buffer.
	int dataBufferSize; // Input for SCAN and POPULATE, size of SMAPI output buffer
	int byteCount; // Bytes processed from SMAPI returned data buffer
	int outStringByteCount; // Output parm from SCAN
	int outStructCount[MAX_STRUCT_ARRAYS]; // Output parm from SCAN
	int outStructSizes[MAX_STRUCT_ARRAYS]; // Output parm from SCAN
	void * inStructAddrs[MAX_STRUCT_ARRAYS];// Input parm for POPULATE
	char * inStringCursor; // Input string block pointer for POPULATE
} tableParserParms;

#define PARSER_ERROR_INVALID_TABLE       -4002
#define PARSER_ERROR_INVALID_STRING_SIZE -4003

#define ntohll(x) (((unsigned long long)(ntohl((int)((x << 32) >> 32))) << 32) | (unsigned int)ntohl(((int)(x >> 32))))
#define htonll(x) ntohll(x)

#define PUT_INT(_inInt_,_outBuf_) \
 ({ int _int;                     \
    _int = htonl(_inInt_) ;       \
    memcpy(_outBuf_, &_int, 4);   \
    _outBuf_ += 4;                \
 })

#define GET_INT(_outInt_,_inBuf_) \
 ({ int _int;                     \
    memcpy(&_int, _inBuf_, 4);    \
    _outInt_ = ntohl(_int) ;      \
    _inBuf_ += 4;                 \
 })

#define PUT_64INT(_in64Int_,_outBuf_) \
 ({ long long _64int;                  \
    _64int = htonll(_in64Int_) ;       \
    memcpy(_outBuf_, &_64int, 8);      \
    _outBuf_ += 8;                     \
 })

#define GET_64INT(_out64Int_,_inBuf_) \
 ({ long long _64int;                 \
    memcpy(&_64int, _inBuf_, 8);      \
    _out64Int_ = ntohll(_64int) ;     \
    _inBuf_ += 8;                     \
 })

int parseBufferWithTable(struct _VmApiInternalContext* vmapiContextP,
		enum tableParserModes mode, tableLayout table, tableParserParms *parms);

int getAndParseSmapiBuffer(struct _VmApiInternalContext* vmapiContextP,
		char * * inputBufferPointerPointer, int inputBufferSize,
		tableLayout parserTable, char * parserTableName, char * * outData);

#ifdef __cplusplus
}
#endif
#endif
