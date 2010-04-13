// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _VMAPI_STATIC_H
#define _VMAPI_STATIC_H
#include "smPublic.h"
#include "smapiTableParser.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Static_Image_Changes_Activate_DM
typedef commonOutputFields vmApiStaticImageChangesActivateDmOutput;

//  Parser table for Static_Image_Changes_Activate_DM
static tableLayout Static_Image_Changes_Activate_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiStaticImageChangesActivateDmOutput) }, { APITYPE_INT4, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiStaticImageChangesActivateDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiStaticImageChangesActivateDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiStaticImageChangesActivateDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smStatic_Image_Changes_Activate_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		vmApiStaticImageChangesActivateDmOutput ** outData);

// Static_Image_Changes_Deactivate_DM
typedef commonOutputFields vmApiStaticImageChangesDeactivateDmOutput;

//  Parser table for Static_Image_Changes_Deactivate_DM
static tableLayout Static_Image_Changes_Deactivate_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiStaticImageChangesDeactivateDmOutput) }, { APITYPE_INT4, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiStaticImageChangesDeactivateDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiStaticImageChangesDeactivateDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiStaticImageChangesDeactivateDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smStatic_Image_Changes_Deactivate_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		vmApiStaticImageChangesDeactivateDmOutput ** outData);

// Static_Image_Changes_Immediate_DM
typedef commonOutputFields vmApiStaticImageChangesImmediateDmOutput;

// Parser table for Static_Image_Changes_Immediate_DM
static tableLayout Static_Image_Changes_Immediate_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiStaticImageChangesImmediateDmOutput) }, { APITYPE_INT4, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiStaticImageChangesImmediateDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiStaticImageChangesImmediateDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiStaticImageChangesImmediateDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smStatic_Image_Changes_Immediate_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		vmApiStaticImageChangesImmediateDmOutput ** outData);

#ifdef __cplusplus
}
#endif

#endif
