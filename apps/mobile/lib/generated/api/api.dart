//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

library wattbyte_api;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

part 'api_client.dart';
part 'api_helper.dart';
part 'api_exception.dart';
part 'auth/authentication.dart';
part 'auth/api_key_auth.dart';
part 'auth/oauth.dart';
part 'auth/http_basic_auth.dart';
part 'auth/http_bearer_auth.dart';

part 'api/account_api.dart';
part 'api/ai_api.dart';
part 'api/auth_api.dart';
part 'api/config_api.dart';
part 'api/devices_api.dart';
part 'api/electricity_api.dart';
part 'api/ops_api.dart';
part 'api/region_api.dart';
part 'api/usage_api.dart';

part 'model/ai_generate_request.dart';
part 'model/ai_generate_response.dart';
part 'model/ai_input.dart';
part 'model/ai_output.dart';
part 'model/api_v1_auth_apple_post_request.dart';
part 'model/app_config_dto.dart';
part 'model/app_config_dto_ai.dart';
part 'model/app_config_dto_ai_daily_limits.dart';
part 'model/app_config_dto_features.dart';
part 'model/app_config_dto_minimum_app_version.dart';
part 'model/auth_response.dart';
part 'model/change_password_request.dart';
part 'model/cloud_data_delete_response.dart';
part 'model/cloud_data_deleted_counts.dart';
part 'model/cloud_export_ai_generation.dart';
part 'model/cloud_export_charging_summary.dart';
part 'model/cloud_export_daily_usage.dart';
part 'model/cloud_export_document.dart';
part 'model/cloud_export_limits.dart';
part 'model/cloud_export_monthly_summary.dart';
part 'model/cloud_export_settings.dart';
part 'model/cloud_export_subscription.dart';
part 'model/cloud_export_truncated.dart';
part 'model/daily_usage_dto.dart';
part 'model/device_dto.dart';
part 'model/device_list_response.dart';
part 'model/device_register_request.dart';
part 'model/device_specification_dto.dart';
part 'model/electricity_price_dto.dart';
part 'model/error_response.dart';
part 'model/error_response_error.dart';
part 'model/health_response.dart';
part 'model/login_request.dart';
part 'model/ready_response.dart';
part 'model/refresh_request.dart';
part 'model/region_response.dart';
part 'model/register_request.dart';
part 'model/session_dto.dart';
part 'model/session_list_response.dart';
part 'model/token_pair.dart';
part 'model/update_me_request.dart';
part 'model/update_user_settings_request.dart';
part 'model/usage_daily_response.dart';
part 'model/usage_sync_request.dart';
part 'model/usage_sync_response.dart';
part 'model/user_dto.dart';
part 'model/user_settings_dto.dart';

/// An [ApiClient] instance that uses the default values obtained from
/// the OpenAPI specification file.
var defaultApiClient = ApiClient();

const _delimiters = {'csv': ',', 'ssv': ' ', 'tsv': '\t', 'pipes': '|'};
const _dateEpochMarker = 'epoch';
const _deepEquality = DeepCollectionEquality();
final _dateFormatter = DateFormat('yyyy-MM-dd');
final _regList = RegExp(r'^List<(.*)>$');
final _regSet = RegExp(r'^Set<(.*)>$');
final _regMap = RegExp(r'^Map<String,(.*)>$');

bool _isEpochMarker(String? pattern) =>
    pattern == _dateEpochMarker || pattern == '/$_dateEpochMarker/';
