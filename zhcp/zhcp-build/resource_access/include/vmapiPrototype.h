// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _VMAPI_PROTOTYPE_H
#define _VMAPI_PROTOTYPE_H
#include "smPublic.h"
#include "smapiTableParser.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Prototype_Create_DM
typedef struct _vmApiPrototypeRecordList { // Common structure for Prototype_Query_DM, create, replace
	char * recordName;
	int recordNameLength;
} vmApiPrototypeRecordList;

typedef commonOutputFields vmApiPrototypeCreateDmOutput;

int smPrototype_Create_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, int recordArrayCount,
		vmApiPrototypeRecordList * recordArrayData,
		vmApiPrototypeCreateDmOutput ** outData);

// Parser table for Prototype_Create_DM
static tableLayout Prototype_Create_DM_Layout = { { APITYPE_BASE_STRUCT_LEN, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiPrototypeCreateDmOutput) },
		{ APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiPrototypeCreateDmOutput, requestId) }, { APITYPE_INT4, 4,
				4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiPrototypeCreateDmOutput, returnCode) }, {
				APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiPrototypeCreateDmOutput, reasonCode) }, {
				APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

// Prototype_Delete_DM
typedef commonOutputFields vmApiPrototypeDeleteDmOutput;

int smPrototype_Delete_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, vmApiPrototypeDeleteDmOutput ** outData);

// Parser table for Prototype_Delete_DM
static tableLayout Prototype_Delete_DM_Layout = { { APITYPE_BASE_STRUCT_LEN, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiPrototypeDeleteDmOutput) },
		{ APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiPrototypeDeleteDmOutput, requestId) }, { APITYPE_INT4, 4,
				4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiPrototypeDeleteDmOutput, returnCode) }, {
				APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiPrototypeDeleteDmOutput, reasonCode) }, {
				APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

// Prototype_Name_Query_DM
typedef struct _vmApiPrototypeNameList { // Common structure for Prototype_Name_Query_DM,
	char * name;
} vmApiPrototypeNameList;

typedef struct _vmApiPrototypeNameQueryDm {
	commonOutputFields common;
	int nameArrayCount;
	vmApiPrototypeNameList * nameList;
} vmApiPrototypeNameQueryDmOutput;

int smPrototype_Name_Query_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, vmApiPrototypeNameQueryDmOutput ** outData);

// Parser table for Prototype_Name_Query_DM
static tableLayout Prototype_Name_Query_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiPrototypeNameQueryDmOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiPrototypeNameQueryDmOutput,
				common.requestId) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiPrototypeNameQueryDmOutput,
				common.returnCode) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiPrototypeNameQueryDmOutput,
				common.reasonCode) },

{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiPrototypeNameQueryDmOutput, nameList) }, {
		APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		offsetof(vmApiPrototypeNameQueryDmOutput, nameArrayCount) }, {
		APITYPE_NOBUFFER_STRUCT_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
		sizeof(vmApiPrototypeNameList) }, { APITYPE_STRING_LEN, 1, 8,
		STRUCT_INDX_1, NEST_LEVEL_1, offsetof(vmApiPrototypeNameList, name) },
		{ APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

// Prototype_Query_DM
typedef struct _vmApiPrototypeQueryDm {
	commonOutputFields common;
	int recordArrayCount;
	vmApiPrototypeRecordList * recordList;
} vmApiPrototypeQueryDmOutput;

int smPrototype_Query_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, vmApiPrototypeQueryDmOutput ** outData);

// Parser table for Prototype_Query_DM
static tableLayout Prototype_Query_DM_Layout = { { APITYPE_BASE_STRUCT_LEN, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiPrototypeQueryDmOutput) },
		{ APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiPrototypeQueryDmOutput, common.requestId) }, {
				APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiPrototypeQueryDmOutput, common.returnCode) }, {
				APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiPrototypeQueryDmOutput, common.reasonCode) },

		{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiPrototypeQueryDmOutput, recordList) }, {
				APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
				offsetof(vmApiPrototypeQueryDmOutput, recordArrayCount) }, {
				APITYPE_NOBUFFER_STRUCT_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
				sizeof(vmApiPrototypeRecordList) }, { APITYPE_CHARBUF_LEN, 1,
				72, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
						vmApiPrototypeRecordList, recordName) }, {
				APITYPE_CHARBUF_COUNT, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
				offsetof(vmApiPrototypeRecordList, recordNameLength) }, {
				APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

// Prototype_Replace_DM
typedef commonOutputFields vmApiPrototypeReplaceDmOutput;

int smPrototype_Replace_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, int recordArrayCount,
		vmApiPrototypeRecordList * recordArrayData,
		vmApiPrototypeReplaceDmOutput ** outData);

// Parser table for Prototype_Replace_DM
static tableLayout Prototype_Replace_DM_Layout = { { APITYPE_BASE_STRUCT_LEN,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiPrototypeReplaceDmOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiPrototypeReplaceDmOutput,
				requestId) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiPrototypeReplaceDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiPrototypeReplaceDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

#ifdef __cplusplus
}
#endif

#endif
