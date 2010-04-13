// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _VMAPI_PROFILE_H
#define _VMAPI_PROFILE_H
#include "smPublic.h"
#include "smapiTableParser.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Profile_Create_DM
// Common structure to hold one profile record (used on profile_query output, input for Create and Replace)
typedef struct _vmApiProfileRecord {
	int profileRecordLength;
	char * recordData;
} vmApiProfileRecord;

typedef commonOutputFields vmApiProfileCreateDmOutput;

// Parser table for Profile_Create_DM
static tableLayout Profile_Create_DM_Layout = { { APITYPE_BASE_STRUCT_LEN, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiProfileCreateDmOutput) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiProfileCreateDmOutput, requestId) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiProfileCreateDmOutput,
				returnCode) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiProfileCreateDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smProfile_Create_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, int profileRecordCount,
		vmApiProfileRecord * profileRecordList,
		vmApiProfileCreateDmOutput ** outData);

// Profile_Delete_DM
typedef commonOutputFields vmApiProfileDeleteDmOutput;

// Parser table for Profile_Delete_DM
static tableLayout Profile_Delete_DM_Layout = { { APITYPE_BASE_STRUCT_LEN, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiProfileDeleteDmOutput) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiProfileDeleteDmOutput, requestId) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiProfileDeleteDmOutput,
				returnCode) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiProfileDeleteDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smProfile_Delete_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, vmApiProfileDeleteDmOutput ** outData);

// Profile_Query_DM
typedef struct _vmApiProfileQueryDmOutput {
	commonOutputFields common;
	int profileRecordCount;
	vmApiProfileRecord * profileRecordList;
} vmApiProfileQueryDmOutput;

// Parser table for Profile_Query_DM
static tableLayout Profile_Query_DM_Layout = { { APITYPE_BASE_STRUCT_LEN, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiProfileQueryDmOutput) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiProfileQueryDmOutput, common.requestId) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiProfileQueryDmOutput,
				common.returnCode) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiProfileQueryDmOutput, common.reasonCode) },

{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiProfileQueryDmOutput, profileRecordList) }, {
		APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		offsetof(vmApiProfileQueryDmOutput, profileRecordCount) }, {
		APITYPE_NOBUFFER_STRUCT_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
		sizeof(vmApiProfileRecord) },
		{ APITYPE_CHARBUF_LEN, 0, 80, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiProfileRecord, recordData) }, { APITYPE_CHARBUF_COUNT, 0,
				4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(vmApiProfileRecord,
						profileRecordLength) }, { APITYPE_END_OF_TABLE, 0, 0,
				0, 0 } };

int smProfile_Query_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, vmApiProfileQueryDmOutput ** outData);

// Profile_Replace_DM
typedef commonOutputFields vmApiProfileReplaceDmOutput;

// Parser table for Profile_Replace_DM
static tableLayout Profile_Replace_DM_Layout = { { APITYPE_BASE_STRUCT_LEN, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiProfileReplaceDmOutput) },
		{ APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiProfileReplaceDmOutput, requestId) }, { APITYPE_INT4, 4,
				4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiProfileReplaceDmOutput, returnCode) }, {
				APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiProfileReplaceDmOutput, reasonCode) }, {
				APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smProfile_Replace_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, int profileRecordCount,
		vmApiProfileRecord * profileRecordList,
		vmApiProfileReplaceDmOutput ** outData);

#ifdef __cplusplus
}
#endif

#endif
