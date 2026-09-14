//
//  zsign.mm
//  feather
//
//  Created by HAHALOSAH on 5/22/24.
//

#import <Foundation/Foundation.h>
#include "zsign.hpp"
#include "common.h"
#include "openssl.h"
#include "macho.h"
#include "bundle.h"
#include "openssl.h"
#include "timer.h"
#include "archive.h"

#include <openssl/ocsp.h>
#include <openssl/x509.h>
#include <openssl/pem.h>
#include <openssl/bio.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/asn1.h>
#include <openssl/evp.h>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <cstring>
#include <cstdlib>

extern "C" {

bool CheckIfSigned(NSString *filePath) {
	ZTimer gtimer;
	@autoreleasepool {
		std::string filePathStr = [filePath UTF8String];
		
		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return false;
		}
		
		bool success = machO.CheckSignature();
		
		machO.Free();
		
		if (success) {
			gtimer.Print(">>> MachO is signed!");
			return true;
		} else {
			gtimer.Print(">>> MachO is not signed.");
			return false;
		}
	}
}

bool InjectDyLib(NSString *filePath, NSString *dylibPath, bool weakInject) {
	ZTimer gtimer;
	@autoreleasepool {
		std::string filePathStr = [filePath UTF8String];
		std::string dylibPathStr = [dylibPath UTF8String];
		
		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return false;
		}
		
		bool success = machO.InjectDylib(weakInject, dylibPathStr.c_str());
		
		machO.Free();
		
		if (success) {
			gtimer.Print(">>> Dylib injected successfully!");
			return true;
		} else {
			gtimer.Print(">>> Failed to inject dylib.");
			return false;
		}
	}
}

bool UninstallDylibs(NSString *filePath, NSArray<NSString *> *dylibPathsArray) {
	ZTimer gtimer;
	@autoreleasepool {
		std::string filePathStr = [filePath UTF8String];
		std::set<std::string> dylibsToRemove;
		
		for (NSString *dylibPath in dylibPathsArray) {
			dylibsToRemove.insert([dylibPath UTF8String]);
		}
		
		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return false;
		}
		
		machO.RemoveDylib(dylibsToRemove);
		
		machO.Free();
		
		gtimer.Print(">>> Dylibs uninstalled successfully!");
		return true;
	}
}

NSArray<NSString *> *ListDylibs(NSString *filePath) {
	ZTimer gtimer;
	@autoreleasepool {
		NSMutableArray<NSString *> *dylibPathsArray = [NSMutableArray array];
		
		std::string filePathStr = [filePath UTF8String];
		
		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return nil;
		}
		
		std::vector<std::string> dylibPaths = machO.ListDylibs();
		
		if (!dylibPaths.empty()) {
			gtimer.Print(">>> List of dylibs in the Mach-O file:");
			for (const std::string &dylibPath : dylibPaths) {
				NSString *dylibPathStr = [NSString stringWithUTF8String:dylibPath.c_str()];
				[dylibPathsArray addObject:dylibPathStr];
			}
		} else {
			gtimer.Print(">>> No dylibs found in the Mach-O file.");
		}
		
		machO.Free();
		
		return [dylibPathsArray copy];
	}
}

bool ChangeDylibPath(NSString *filePath, NSString *oldPath, NSString *newPath) {
	ZTimer gtimer;
	@autoreleasepool {
		std::string filePathStr = [filePath UTF8String];
		std::string oldPathStr = [oldPath UTF8String];
		std::string newPathStr = [newPath UTF8String];
		
		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return false;
		}
		
		bool success = machO.ChangeDylibPath(oldPathStr.c_str(), newPathStr.c_str());
		
		machO.Free();
		
		if (success) {
			gtimer.Print(">>> Dylib path changed successfully!");
			return true;
		} else {
			gtimer.Print(">>> Failed to change dylib path.");
			return false;
		}
	}
}

int zsign(
	NSString *app,
	NSString *prov,
	NSString *key,
	NSString *pass,
	NSString *entitlement,
	NSString *bundleid,
	NSString *displayname,
	NSString *bundleversion,
	bool adhoc,
	bool excludeprovion,
	void(^completionHandler)(BOOL success, NSError *error)
) {
	ZTimer atimer;
	ZTimer gtimer;
	
	bool bForce = true;
	bool bWeakInject = false;
	bool bAdhoc = adhoc;
	bool bSHA256Only = false;
	
	string strCertFile;
	string strPKeyFile;
	string strProvFile;
	string strPassword;
	string strBundleId;
	string strBundleVersion;
	string strDisplayName;
	string strEntitleFile;
	vector<string> arrDylibFiles;
	vector<string> arrDisDylibFiles;
	
	strPKeyFile = [key cStringUsingEncoding:NSUTF8StringEncoding];
	strProvFile = [prov cStringUsingEncoding:NSUTF8StringEncoding];
	strPassword = [pass cStringUsingEncoding:NSUTF8StringEncoding];
	strEntitleFile = [entitlement cStringUsingEncoding:NSUTF8StringEncoding];
	
	strBundleId = [bundleid cStringUsingEncoding:NSUTF8StringEncoding];
	strDisplayName = [displayname cStringUsingEncoding:NSUTF8StringEncoding];
	strBundleVersion = [bundleversion cStringUsingEncoding:NSUTF8StringEncoding];
	
	string strPath = [app cStringUsingEncoding:NSUTF8StringEncoding];
	if (!ZFile::IsFileExists(strPath.c_str())) {
		ZLog::ErrorV(">>> Invalid path! %s\n", strPath.c_str());
		return -1;
	}
	
	ZSignAsset zsa;
	if (!zsa.Init(strCertFile, strPKeyFile, strProvFile, strEntitleFile, strPassword, bAdhoc, bSHA256Only, false)) {
		return -1;
	}
	
	bool bEnableCache = true;
	string strFolder = strPath;
	
	atimer.Reset();
	ZBundle bundle;
	bool bRet = bundle.SignFolder(&zsa, strFolder, strBundleId, strBundleVersion, strDisplayName, arrDylibFiles, bForce, bWeakInject, bEnableCache, excludeprovion);
	ZLog::PrintV(">>> Signing:\t%s %s\n", strPath.c_str(), (bAdhoc ? " (Ad-hoc)" : ""));
	atimer.PrintResult(bRet, ">>> Signed %s!", bRet ? "OK" : "Failed");
	
	NSError* signError = nil;
	if(!bundle.signFailedFiles.empty()) {
		NSDictionary* userInfo = @{
			NSLocalizedDescriptionKey : [NSString stringWithUTF8String:bundle.signFailedFiles.c_str()]
		};
		signError = [NSError errorWithDomain:@"Failed to Sign" code:-1 userInfo:userInfo];
	}
	
	completionHandler(bRet, signError);
	
	gtimer.Print(">>> Done.");
	return bRet ? 0 : -1;
}


int checkCert(
    NSString *prov,
    NSString *key,
    NSString *pass,
    void(^completionHandler)(int status, NSDate* expirationDate, NSString *error)
) {
    if (!key || !prov || !pass) {
        completionHandler(2, nil, @"One or more required paths or password is missing.");
        return -1;
    }

    // Copy tham số sang std::string để block nền tự sở hữu (không phụ thuộc stack/NSString).
    const char *cKey  = [key UTF8String];
    const char *cProv = [prov UTF8String];
    const char *cPass = [pass UTF8String];
    std::string strPKeyFile = cKey  ? cKey  : "";
    std::string strProvFile = cProv ? cProv : "";
    std::string strPassword = cPass ? cPass : "";

    // TOÀN BỘ chạy ĐỒNG BỘ trong 1 block nền: zsa/cert/issuer/OCSP đều sống trọn block
    // => KHÔNG use-after-free, KHÔNG con trỏ rác, và không đơ UI.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        ZSignAsset zsa;
        std::string strCertFile, strEntitleFile;
        if (!zsa.Init(strCertFile, strPKeyFile, strProvFile, strEntitleFile, strPassword, false, false, false)) {
            completionHandler(2, nil, @"Unable to initialize certificate. Please check your password.");
            return;
        }

        X509 *cert = (X509 *)zsa.m_x509Cert;
        if (!cert) { completionHandler(2, nil, @"Error loading certificate"); return; }

        // Issuer CA của Apple theo hash
        BIO *cabio = NULL;
        unsigned long issuerHash = X509_issuer_name_hash(cert);
        if (issuerHash == 0x817d2f7a) {
            cabio = BIO_new_mem_buf(ZSignAsset::s_szAppleDevCACert, (int)strlen(ZSignAsset::s_szAppleDevCACert));
        } else if (issuerHash == 0x9b16b75c) {
            cabio = BIO_new_mem_buf(ZSignAsset::s_szAppleDevCACertG3, (int)strlen(ZSignAsset::s_szAppleDevCACertG3));
        } else {
            completionHandler(2, nil, @"Unable to determine issuer of the certificate. Is it signed by Apple Developer?");
            return;
        }
        if (!cabio) { completionHandler(2, nil, @"Unable to initialize issuer certificate."); return; }
        X509 *issuer = PEM_read_bio_X509(cabio, NULL, 0, NULL);
        BIO_free(cabio);
        if (!issuer) { completionHandler(2, nil, @"Error loading issuer"); return; }

        // Hạn dùng cert (cert còn sống trong block)
        NSDate *expirationDate = nil;
        {
            ASN1_TIME *notAfter = X509_get_notAfter(cert);
            if (notAfter && notAfter->data && notAfter->length > 0) {
                NSString *tail = [[NSString alloc] initWithBytes:notAfter->data length:notAfter->length encoding:NSASCIIStringEncoding];
                if (tail) {
                    NSString *full = [@"20" stringByAppendingString:tail];
                    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
                    fmt.dateFormat = @"yyyyMMddHHmmss'Z'";
                    fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
                    fmt.locale = NSLocale.currentLocale;
                    expirationDate = [fmt dateFromString:full];
                }
            }
        }

        // OCSP URL từ AIA (mặc định Apple WWDR nếu không có)
        std::string ocspHost = "ocsp.apple.com", ocspPort = "80", ocspPath = "/ocsp03-wwdrg301";
        STACK_OF(ACCESS_DESCRIPTION) *aia = (STACK_OF(ACCESS_DESCRIPTION) *)X509_get_ext_d2i(cert, NID_info_access, 0, 0);
        if (aia) {
            for (int i = 0; i < sk_ACCESS_DESCRIPTION_num(aia); i++) {
                ACCESS_DESCRIPTION *ad = sk_ACCESS_DESCRIPTION_value(aia, i);
                if (OBJ_obj2nid(ad->method) == NID_ad_OCSP && ad->location->type == GEN_URI) {
                    ASN1_IA5STRING *u = ad->location->d.uniformResourceIdentifier;
                    if (u && u->data && u->length > 0) {
                        std::string url((const char *)u->data, u->length);
                        std::string rest = url;
                        size_t pp = rest.find("://");
                        if (pp != std::string::npos) rest = rest.substr(pp + 3);
                        size_t slash = rest.find('/');
                        std::string hostport = (slash == std::string::npos) ? rest : rest.substr(0, slash);
                        std::string path = (slash == std::string::npos) ? "/" : rest.substr(slash);
                        size_t colon = hostport.find(':');
                        if (colon != std::string::npos) { ocspHost = hostport.substr(0, colon); ocspPort = hostport.substr(colon + 1); }
                        else { ocspHost = hostport; ocspPort = "80"; }
                        ocspPath = path.empty() ? "/" : path;
                    }
                    break;
                }
            }
            sk_ACCESS_DESCRIPTION_pop_free(aia, ACCESS_DESCRIPTION_free);
        }

        // Dựng OCSP request
        OCSP_CERTID *certId = OCSP_cert_to_id(EVP_sha1(), cert, issuer);
        if (!certId) { X509_free(issuer); completionHandler(2, expirationDate, @"Failed to create cert ID"); return; }
        OCSP_REQUEST *req = OCSP_REQUEST_new();
        if (!req) { OCSP_CERTID_free(certId); X509_free(issuer); completionHandler(2, expirationDate, @"OCSP request alloc failed"); return; }
        if (!OCSP_request_add0_id(req, certId)) { OCSP_REQUEST_free(req); X509_free(issuer); completionHandler(2, expirationDate, @"Add ID failed"); return; }
        OCSP_CERTID *lookupId = OCSP_cert_to_id(EVP_sha1(), cert, issuer); // bản riêng để tra status

        unsigned char *derReq = NULL;
        int derReqLen = i2d_OCSP_REQUEST(req, &derReq);
        OCSP_REQUEST_free(req); // free req + certId nó sở hữu
        if (derReqLen <= 0 || !derReq) { if (lookupId) OCSP_CERTID_free(lookupId); X509_free(issuer); completionHandler(2, expirationDate, @"Serialize failed"); return; }

        // Socket ĐỒNG BỘ tới OCSP responder (chỉ ra mạng tới Apple, giống PHP)
        struct addrinfo hints; memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM;
        struct addrinfo *res = NULL;
        if (getaddrinfo(ocspHost.c_str(), ocspPort.c_str(), &hints, &res) != 0 || !res) {
            OPENSSL_free(derReq); if (lookupId) OCSP_CERTID_free(lookupId); X509_free(issuer);
            completionHandler(2, expirationDate, @"DNS failed"); return;
        }
        int sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
        if (sock < 0) {
            freeaddrinfo(res); OPENSSL_free(derReq); if (lookupId) OCSP_CERTID_free(lookupId); X509_free(issuer);
            completionHandler(2, expirationDate, @"Socket failed"); return;
        }
        if (connect(sock, res->ai_addr, (int)res->ai_addrlen) < 0) {
            close(sock); freeaddrinfo(res); OPENSSL_free(derReq); if (lookupId) OCSP_CERTID_free(lookupId); X509_free(issuer);
            completionHandler(2, expirationDate, @"Connect failed"); return;
        }
        freeaddrinfo(res);

        char reqhdr[512];
        snprintf(reqhdr, sizeof(reqhdr),
            "POST %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: zsign\r\nConnection: close\r\nContent-Type: application/ocsp-request\r\nContent-Length: %d\r\n\r\n",
            ocspPath.c_str(), ocspHost.c_str(), derReqLen);
        std::string reqStr(reqhdr);
        reqStr.append((const char *)derReq, derReqLen);
        OPENSSL_free(derReq);

        const char *sendPtr = reqStr.data();
        size_t sendRemain = reqStr.size();
        bool sendOK = true;
        while (sendRemain > 0) {
            ssize_t sent = send(sock, sendPtr, sendRemain, 0);
            if (sent <= 0) { sendOK = false; break; }
            sendPtr += sent; sendRemain -= (size_t)sent;
        }
        if (!sendOK) { close(sock); if (lookupId) OCSP_CERTID_free(lookupId); X509_free(issuer); completionHandler(2, expirationDate, @"Send failed"); return; }

        std::string resp; char rbuf[4096];
        while (resp.find("\r\n\r\n") == std::string::npos) {
            ssize_t br = recv(sock, rbuf, sizeof(rbuf), 0);
            if (br <= 0) break;
            resp.append(rbuf, br);
        }
        size_t he = resp.find("\r\n\r\n");
        if (he == std::string::npos) { close(sock); if (lookupId) OCSP_CERTID_free(lookupId); X509_free(issuer); completionHandler(2, expirationDate, @"Invalid response"); return; }

        long contentLength = 0;
        {
            size_t clPos = resp.find("Content-Length:");
            if (clPos == std::string::npos) clPos = resp.find("content-length:");
            if (clPos != std::string::npos) contentLength = atol(resp.c_str() + clPos + 15);
        }
        size_t bodyHave = resp.size() - he - 4;
        while (contentLength > 0 && bodyHave < (size_t)contentLength) {
            ssize_t br = recv(sock, rbuf, sizeof(rbuf), 0);
            if (br <= 0) break;
            resp.append(rbuf, br); bodyHave += (size_t)br;
        }
        close(sock);

        const unsigned char *bodyPtr = (const unsigned char *)resp.data() + he + 4;
        long bodyLen = (long)(resp.size() - he - 4);
        if (bodyLen <= 0) { if (lookupId) OCSP_CERTID_free(lookupId); X509_free(issuer); completionHandler(2, expirationDate, @"Empty OCSP body"); return; }

        OCSP_RESPONSE *oresp = d2i_OCSP_RESPONSE(NULL, &bodyPtr, bodyLen);
        if (!oresp) { if (lookupId) OCSP_CERTID_free(lookupId); X509_free(issuer); completionHandler(2, expirationDate, @"Parse failed"); return; }
        if (OCSP_response_status(oresp) != OCSP_RESPONSE_STATUS_SUCCESSFUL) {
            OCSP_RESPONSE_free(oresp); if (lookupId) OCSP_CERTID_free(lookupId); X509_free(issuer);
            completionHandler(2, expirationDate, @"OCSP responder error"); return;
        }
        OCSP_BASICRESP *basic = OCSP_response_get1_basic(oresp);
        if (!basic) { OCSP_RESPONSE_free(oresp); if (lookupId) OCSP_CERTID_free(lookupId); X509_free(issuer); completionHandler(2, expirationDate, @"No basic response"); return; }

        int result = 2; // mặc định unknown
        if (lookupId) {
            int cs = -1, reason = 0;
            ASN1_GENERALIZEDTIME *rt = NULL, *tu = NULL, *nu = NULL;
            if (OCSP_resp_find_status(basic, lookupId, &cs, &reason, &rt, &tu, &nu) == 1) {
                if (cs == V_OCSP_CERTSTATUS_GOOD) result = 0;
                else if (cs == V_OCSP_CERTSTATUS_REVOKED) result = 1;
                else result = 2;
            }
        }

        OCSP_BASICRESP_free(basic);
        OCSP_RESPONSE_free(oresp);
        if (lookupId) OCSP_CERTID_free(lookupId);
        X509_free(issuer);

        completionHandler(result, expirationDate, nil);
    });

    return 1;
}



}
