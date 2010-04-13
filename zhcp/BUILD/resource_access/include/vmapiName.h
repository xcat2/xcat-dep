// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _VMAPI_NAME_H
#define _VMAPI_NAME_H
#include "smPublic.h"
#include "smapiTableParser.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Name_List_Add
typedef commonOutputFields vmApiNameListAddOutput;

int smName_List_Add(struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * name, vmApiNameListAddOutput ** outData);

// Parser table for Name_List_Add
static tableLayout Name_List_Add_Layout = { { APITYPE_BASE_STRUCT_LEN, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiNameListAddOutput) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiNameListAddOutput, requestId) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiNameListAddOutput,
				returnCode) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiNameListAddOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

// Name_List_Destroy
typedef commonOutputFields vmApiNameListDestroyOutput;

int smName_List_Destroy(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, vmApiNameListDestroyOutput ** outData);

// Parser table for Name_List_Destroy
static tableLayout Name_List_Destroy_Layout = { { APITYPE_BASE_STRUCT_LEN, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiNameListDestroyOutput) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiNameListDestroyOutput, requestId) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiNameListDestroyOutput,
				returnCode) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiNameListDestroyOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

// Name_List_Query
typedef struct _vmApiNameList { // Common structure for Name_List_Query,
	char * imageName;
} vmApiNameList;

typedef struct _vmApiNameListQuery {
	commonOutputFields common;
	int nameArrayCount;
	vmApiNameList * nameList;
} vmApiNameListQueryOutput;

int smName_List_Query(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, vmApiNameListQueryOutput ** outData);

// Parser table for Name_List_Query
static tableLayout Name_List_Query_Layout = { { APITYPE_BASE_STRUCT_LEN, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiNameListQueryOutput) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiNameListQueryOutput, common.requestId) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiNameListQueryOutput,
				common.returnCode) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiNameListQueryOutput, common.reasonCode) },

{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiNameListQueryOutput, nameList) }, { APITYPE_ARRAY_STRUCT_COUNT, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiNameListQueryOutput,
				nameArrayCount) }, { APITYPE_NOBUFFER_STRUCT_LEN, 4, 4,
		STRUCT_INDX_1, NEST_LEVEL_1, sizeof(vmApiNameList) }, {
		APITYPE_STRING_LEN, 1, 8, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiNameList, imageName) },
		{ APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

// Name_List_Remove
typedef commonOutputFields vmApiNameListRemoveOutput;

int smName_List_Remove(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, char * name,
		vmApiNameListRemoveOutput ** outData);

// Parser table for Name_List_Remove
static tableLayout Name_List_Remove_Layout = { { APITYPE_BASE_STRUCT_LEN, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiNameListRemoveOutput) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiNameListRemoveOutput, requestId) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiNameListRemoveOutput,
				returnCode) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiNameListRemoveOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

#ifdef __cplusplus
}
#endif

#endif
