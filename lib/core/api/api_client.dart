import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import '../config.dart';
import '../storage/secret_store.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient(this.secrets) : dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 20))) {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await secrets.token; final install = await secrets.installationUuid(); final device = await secrets.deviceUuid(); final info = await DeviceInfoPlugin().androidInfo;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      options.headers.addAll({'Accept':'application/json','X-Installation-UUID':install,'X-Device-UUID':device,'X-App-Version':AppConfig.appVersion,'X-Platform':'android','X-OS-Version':info.version.release});
      handler.next(options);
    }));
  }
  final SecretStore secrets; final Dio dio; void Function()? onAuthRevoked;
  String path(String raw) { final base = dio.options.baseUrl.replaceFirst(RegExp(r'/+$'), ''); final clean = raw.replaceFirst(RegExp(r'^/+'), ''); return '$base/$clean'; }
  Future<dynamic> get(String p, {Map<String,dynamic>? query}) => _send(() => dio.getUri(Uri.parse(path(p)).replace(queryParameters: query?.map((k,v)=>MapEntry(k,'$v')))));
  Future<dynamic> post(String p, {Object? data, Map<String,String>? headers}) => _send(() => dio.postUri(Uri.parse(path(p)), data: data, options: Options(headers: headers)));
  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async { try { final r=await call(); final body=r.data; if(body is Map && body['success']==true)return body['data']; throw ApiException(status:r.statusCode,message:'Invalid server response.'); } on DioException catch(e){ final body=e.response?.data; final err=body is Map?body['error']:null; final details=err is Map?err['details']:null; final fields=<String,List<String>>{}; if(details is Map){for(final entry in details.entries){fields['${entry.key}']=(entry.value is List?entry.value:['${entry.value}']).map((x)=>'$x').toList();}} final code=err is Map?err['code']?.toString():null; final msg=err is Map?err['message']?.toString():(e.error is SocketException?'No internet connection.':'Request failed.'); final status=e.response?.statusCode; if (status==401 || code=='DEVICE_REVOKED') onAuthRevoked?.call(); throw ApiException(status:status,message:msg??'Request failed.',code:code,fieldErrors:fields,retryable:status==null||status>=500); } }
}
