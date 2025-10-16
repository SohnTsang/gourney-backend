/**
 * API Version Guard
 * Ensures clients are using the correct API version
 * Supports both header and path-based versioning
 */

export interface ApiVersionConfig {
  currentVersion: string;
  supportedVersions: string[];
  deprecatedVersions?: string[];
  versionHeader?: string;
  requireVersion?: boolean;
}

const DEFAULT_CONFIG: ApiVersionConfig = {
  currentVersion: 'v1',
  supportedVersions: ['v1'],
  deprecatedVersions: [],
  versionHeader: 'X-API-Version',
  requireVersion: true
};

export interface ApiVersionResult {
  valid: boolean;
  version?: string;
  isDeprecated?: boolean;
  error?: string;
  headers?: Record<string, string>;
}

/**
 * Checks API version from request headers or path
 * Returns validation result with appropriate headers
 */
export function checkApiVersion(
  request: Request,
  config: Partial<ApiVersionConfig> = {}
): ApiVersionResult {
  const cfg = { ...DEFAULT_CONFIG, ...config };
  
  // Extract version from multiple sources
  const headerVersion = request.headers.get(cfg.versionHeader || 'X-API-Version');
  const pathVersion = extractVersionFromPath(request.url);
  
  // Prefer header version over path version
  const version = headerVersion || pathVersion;
  
  // If no version and it's required, reject
  if (!version && cfg.requireVersion) {
    return {
      valid: false,
      error: `API version required. Use ${cfg.versionHeader} header or /v1 path prefix`,
      headers: {
        [cfg.versionHeader || 'X-API-Version']: cfg.currentVersion,
        'X-API-Version-Required': 'true'
      }
    };
  }
  
  // If no version but not required, use current
  if (!version && !cfg.requireVersion) {
    return {
      valid: true,
      version: cfg.currentVersion,
      headers: {
        [cfg.versionHeader || 'X-API-Version']: cfg.currentVersion
      }
    };
  }
  
  // Check if version is supported
  if (!cfg.supportedVersions.includes(version!)) {
    return {
      valid: false,
      version,
      error: `API version ${version} is not supported. Supported versions: ${cfg.supportedVersions.join(', ')}`,
      headers: {
        [cfg.versionHeader || 'X-API-Version']: cfg.currentVersion,
        'X-API-Supported-Versions': cfg.supportedVersions.join(', ')
      }
    };
  }
  
  // Check if version is deprecated
  const isDeprecated = cfg.deprecatedVersions?.includes(version!) || false;
  
  return {
    valid: true,
    version,
    isDeprecated,
    headers: {
      [cfg.versionHeader || 'X-API-Version']: version!,
      ...(isDeprecated ? {
        'X-API-Version-Deprecated': 'true',
        'X-API-Version-Sunset': getSunsetDate(version!),
        'X-API-Version-Latest': cfg.currentVersion
      } : {})
    }
  };
}

/**
 * Extracts version from URL path
 * Looks for /v1, /v2, etc. at the beginning of the path
 */
function extractVersionFromPath(url: string): string | null {
  try {
    const urlObj = new URL(url);
    const pathMatch = urlObj.pathname.match(/^\/?(v\d+)\//);
    return pathMatch ? pathMatch[1] : null;
  } catch {
    return null;
  }
}

/**
 * Returns sunset date for deprecated versions
 * In production, this would come from configuration
 */
function getSunsetDate(version: string): string {
  // Example: deprecated versions sunset 90 days after deprecation
  const sunsetDate = new Date();
  sunsetDate.setDate(sunsetDate.getDate() + 90);
  return sunsetDate.toISOString();
}

/**
 * Middleware wrapper for API version checking
 * Use this to wrap edge functions
 */
export function withApiVersion(
  handler: (req: Request) => Promise<Response>,
  config?: Partial<ApiVersionConfig>
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    const versionCheck = checkApiVersion(req, config);
    
    if (!versionCheck.valid) {
      return new Response(
        JSON.stringify({
          error: versionCheck.error,
          version: versionCheck.version
        }),
        {
          status: 400,
          headers: {
            'Content-Type': 'application/json',
            ...versionCheck.headers
          }
        }
      );
    }
    
    // Add version headers to the response
    const response = await handler(req);
    
    if (versionCheck.headers) {
      Object.entries(versionCheck.headers).forEach(([key, value]) => {
        response.headers.set(key, value);
      });
    }
    
    // Log deprecated version usage for monitoring
    if (versionCheck.isDeprecated) {
      console.warn(`Deprecated API version ${versionCheck.version} used`, {
        url: req.url,
        userAgent: req.headers.get('user-agent'),
        timestamp: new Date().toISOString()
      });
    }
    
    return response;
  };
}

/**
 * Strips version prefix from URL path
 * Useful for routing after version validation
 */
export function stripVersionFromPath(path: string): string {
  return path.replace(/^\/?(v\d+)\//, '/');
}