#!/usr/bin/env python3
"""
API Discovery Script for prompt-inspector

Scans a project directory to find:
1. Frontend API calls (axios, fetch, ky, custom instances, etc.)
2. Backend API endpoints (Express, FastAPI, NestJS, Next.js API routes, etc.)
3. OpenAPI/Swagger specification files

Usage:
    python discover_apis.py <project_path> [--output json|markdown]
"""

import os
import re
import json
import argparse
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import Optional, Set

@dataclass
class APICall:
    """Represents a discovered API call or endpoint"""
    type: str  # 'frontend', 'backend', or 'spec'
    method: str  # GET, POST, PUT, DELETE, PATCH
    path: str  # API path/URL
    file: str  # Source file
    line: int  # Line number
    library: str  # axios, fetch, express, openapi, etc.
    instance_name: Optional[str] = None  # Custom instance name if applicable
    function_name: Optional[str] = None  # Function/handler name if available

# HTTP methods to detect
HTTP_METHODS = {'get', 'post', 'put', 'delete', 'patch', 'head', 'options'}
HTTP_METHODS_UPPER = {m.upper() for m in HTTP_METHODS}

# Known HTTP client libraries and their creation patterns
HTTP_CLIENT_CREATORS = {
    'axios': [r'axios\.create\s*\(', r'import\s+axios\s+from'],
    'ky': [r'ky\.create\s*\(', r'import\s+ky\s+from'],
    'got': [r'got\.extend\s*\(', r'import\s+got\s+from'],
    'superagent': [r'import\s+superagent\s+from', r'require\s*\(\s*[\'"]superagent[\'"]\s*\)'],
    'ofetch': [r'ofetch\.create\s*\(', r'\$fetch', r'import.*from\s*[\'"]ofetch[\'"]'],
    'wretch': [r'wretch\s*\(', r'import\s+wretch\s+from'],
    'redaxios': [r'import\s+redaxios\s+from', r'redaxios\.create\s*\('],
    'apisauce': [r'create\s*\(\s*\{[^}]*baseURL', r'import.*from\s*[\'"]apisauce[\'"]'],
}

# Patterns to find custom HTTP client instance declarations
INSTANCE_DECLARATION_PATTERNS = [
    # export const apiClient = axios.create(...)
    r'(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:axios|ky|got|superagent|wretch|redaxios)(?:\.create|\.extend)?\s*\(',
    # const api = axios.create(...)
    r'(?:const|let|var)\s+(\w+)\s*=\s*\w+\.create\s*\(\s*\{[^}]*baseURL',
    # export const http = new HttpClient(...)
    r'(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*new\s+\w*(?:Http|Api|Client|Service)\w*\s*\(',
]

# Common HTTP client instance names (fallback detection)
COMMON_INSTANCE_NAMES = {
    'api', 'apiClient', 'client', 'http', 'httpClient',
    'request', 'requests', 'axios', 'instance', 'service',
    'fetcher', 'apiService', 'httpService', 'restClient',
}

IGNORED_DIRS = {
    'node_modules', '.git', '.next', 'dist', 'build',
    '__pycache__', '.venv', 'venv', 'coverage', '.turbo'
}

FRONTEND_EXTENSIONS = {'.js', '.jsx', '.ts', '.tsx', '.mjs'}
BACKEND_EXTENSIONS = {'.js', '.ts', '.py', '.mjs'}
SPEC_EXTENSIONS = {'.json', '.yaml', '.yml'}


def should_skip_dir(dir_name: str) -> bool:
    return dir_name in IGNORED_DIRS or dir_name.startswith('.')


def find_http_client_instances(content: str) -> Set[str]:
    """Find custom HTTP client instance names in the file"""
    instances = set()

    for pattern in INSTANCE_DECLARATION_PATTERNS:
        for match in re.finditer(pattern, content, re.MULTILINE):
            if match.group(1):
                instances.add(match.group(1))

    return instances


def extract_url_from_match(match_str: str) -> Optional[str]:
    """Extract URL/path from various string formats"""
    # Remove TypeScript generics like <T> or <ResponseType>
    match_str = re.sub(r'<[^>]+>\s*', '', match_str)

    # Handle template literals: `${baseUrl}/path` -> extract /path part
    template_match = re.search(r'`[^`]*(/[^`\$]+)`', match_str)
    if template_match:
        return template_match.group(1)

    # Handle simple strings: '/api/users' or "/api/users"
    string_match = re.search(r'[\'"`](/[^\'"`\s]+)[\'"`]', match_str)
    if string_match:
        return string_match.group(1)

    # Handle full URLs
    url_match = re.search(r'[\'"`](https?://[^\'"`\s]+)[\'"`]', match_str)
    if url_match:
        return url_match.group(1)

    return None


def find_frontend_apis(file_path: Path, content: str) -> list[APICall]:
    """Find frontend API calls in a file"""
    apis = []

    # Find custom instances in this file
    custom_instances = find_http_client_instances(content)

    # Build dynamic pattern for HTTP method calls
    # Matches: instanceName.method<T>('/path', ...) or instanceName.method('/path', ...)
    all_instances = custom_instances | COMMON_INSTANCE_NAMES | {'axios', 'ky', 'got', 'superagent', 'fetch'}

    # Pattern 1: instance.method<T?>('/path') - covers axios, ky, got, custom instances
    # Handles: apiClient.post<LoginResponse>('/v1/accounts/login/email', data)
    methods_pattern = '|'.join(HTTP_METHODS)
    instance_pattern = '|'.join(re.escape(name) for name in all_instances)

    # Generic pattern for any potential HTTP client call
    # Match: word.httpMethod<optional generic>( string or template literal
    generic_method_pattern = rf'(\w+)\.({methods_pattern})\s*(?:<[^>]*>)?\s*\(\s*([\'"`][^)]+)'

    for match in re.finditer(generic_method_pattern, content, re.IGNORECASE):
        instance_name = match.group(1)
        method = match.group(2).upper()
        url_part = match.group(3)

        # Skip if it doesn't look like an HTTP client call
        if instance_name.lower() in {'console', 'math', 'array', 'object', 'string', 'promise', 'window', 'document'}:
            continue

        url = extract_url_from_match(url_part)
        if not url:
            continue

        line_num = content[:match.start()].count('\n') + 1

        # Determine library
        library = 'unknown'
        if instance_name in custom_instances:
            library = 'custom-instance'
        elif instance_name.lower() in {'axios'}:
            library = 'axios'
        elif instance_name.lower() in {'ky'}:
            library = 'ky'
        elif instance_name.lower() in {'got'}:
            library = 'got'
        elif instance_name in COMMON_INSTANCE_NAMES:
            library = 'http-client'

        apis.append(APICall(
            type='frontend',
            method=method,
            path=url,
            file=str(file_path),
            line=line_num,
            library=library,
            instance_name=instance_name if instance_name not in {'axios', 'ky', 'got', 'fetch'} else None
        ))

    # Pattern 2: fetch('/path', { method: 'POST' }) or fetch('/path')
    fetch_pattern = r'fetch\s*\(\s*([\'"`][^\'"`]+[\'"`])\s*(?:,\s*\{[^}]*method:\s*[\'"`](\w+)[\'"`])?'
    for match in re.finditer(fetch_pattern, content, re.IGNORECASE):
        url = extract_url_from_match(match.group(1))
        if not url:
            continue
        method = match.group(2).upper() if match.group(2) else 'GET'
        line_num = content[:match.start()].count('\n') + 1

        apis.append(APICall(
            type='frontend',
            method=method,
            path=url,
            file=str(file_path),
            line=line_num,
            library='fetch'
        ))

    # Pattern 3: useSWR('/api/users') or useQuery(['/api/users'])
    swr_pattern = r'useSWR\s*\(\s*[\'"`]([^\'"`]+)[\'"`]'
    for match in re.finditer(swr_pattern, content):
        url = match.group(1)
        if url.startswith('/') or url.startswith('http'):
            line_num = content[:match.start()].count('\n') + 1
            apis.append(APICall(
                type='frontend',
                method='GET',
                path=url,
                file=str(file_path),
                line=line_num,
                library='swr'
            ))

    # Pattern 4: useQuery with fetch
    query_pattern = r'useQuery\s*\([^)]*fetch\s*\(\s*[\'"`]([^\'"`]+)[\'"`]'
    for match in re.finditer(query_pattern, content):
        url = match.group(1)
        if url.startswith('/') or url.startswith('http'):
            line_num = content[:match.start()].count('\n') + 1
            apis.append(APICall(
                type='frontend',
                method='GET',
                path=url,
                file=str(file_path),
                line=line_num,
                library='react-query'
            ))

    return apis


def find_backend_apis(file_path: Path, content: str) -> list[APICall]:
    """Find backend API endpoints in a file"""
    apis = []

    # Detect Next.js API routes from file path
    if '/app/api/' in str(file_path) or '/pages/api/' in str(file_path):
        path_str = str(file_path)
        if '/app/api/' in path_str:
            route = path_str.split('/app/api/')[-1]
            route = '/api/' + route.replace('/route.ts', '').replace('/route.js', '')
        else:
            route = path_str.split('/pages/api/')[-1]
            route = '/api/' + route.replace('.ts', '').replace('.js', '')

        # Find exported HTTP methods
        for match in re.finditer(r'export\s+(async\s+)?function\s+(GET|POST|PUT|DELETE|PATCH)', content):
            method = match.group(2)
            line_num = content[:match.start()].count('\n') + 1
            apis.append(APICall(
                type='backend',
                method=method,
                path=route.replace('[', '{').replace(']', '}'),
                file=str(file_path),
                line=line_num,
                library='nextjs-api'
            ))

        for match in re.finditer(r'export\s+const\s+(GET|POST|PUT|DELETE|PATCH)\s*=', content):
            method = match.group(1)
            line_num = content[:match.start()].count('\n') + 1
            apis.append(APICall(
                type='backend',
                method=method,
                path=route.replace('[', '{').replace(']', '}'),
                file=str(file_path),
                line=line_num,
                library='nextjs-api'
            ))

    # Express/Hono style: app.get('/path', ...) or router.post('/path', ...)
    express_pattern = r'(app|router)\.(get|post|put|delete|patch)\s*\(\s*[\'"`]([^\'"`]+)[\'"`]'
    for match in re.finditer(express_pattern, content, re.IGNORECASE):
        method = match.group(2).upper()
        path = match.group(3)
        line_num = content[:match.start()].count('\n') + 1
        apis.append(APICall(
            type='backend',
            method=method,
            path=path,
            file=str(file_path),
            line=line_num,
            library='express'
        ))

    # FastAPI style: @app.get('/path')
    fastapi_pattern = r'@(?:app|router)\.(get|post|put|delete|patch)\s*\(\s*[\'"`]([^\'"`]+)[\'"`]'
    for match in re.finditer(fastapi_pattern, content, re.IGNORECASE):
        method = match.group(1).upper()
        path = match.group(2)
        line_num = content[:match.start()].count('\n') + 1
        apis.append(APICall(
            type='backend',
            method=method,
            path=path,
            file=str(file_path),
            line=line_num,
            library='fastapi'
        ))

    # NestJS style: @Get('/path'), @Post(), etc.
    nestjs_pattern = r'@(Get|Post|Put|Delete|Patch)\s*\(\s*[\'"`]?([^\'"`\)]*)[\'"`]?\s*\)'
    for match in re.finditer(nestjs_pattern, content):
        method = match.group(1).upper()
        path = match.group(2) if match.group(2) else '/'
        line_num = content[:match.start()].count('\n') + 1
        apis.append(APICall(
            type='backend',
            method=method,
            path=path,
            file=str(file_path),
            line=line_num,
            library='nestjs'
        ))

    return apis


def find_openapi_specs(file_path: Path, content: str) -> list[APICall]:
    """Parse OpenAPI/Swagger specification files"""
    apis = []

    try:
        if file_path.suffix == '.json':
            spec = json.loads(content)
        else:
            # For YAML, try to parse as JSON-like structure
            # In production, you'd use pyyaml
            return apis

        # Check if this is an OpenAPI/Swagger spec
        if not ('openapi' in spec or 'swagger' in spec):
            return apis

        # Get base path
        base_path = ''
        if 'basePath' in spec:  # Swagger 2.0
            base_path = spec['basePath']
        elif 'servers' in spec and spec['servers']:  # OpenAPI 3.x
            server_url = spec['servers'][0].get('url', '')
            # Extract path from URL if present
            if '/' in server_url.replace('://', ''):
                base_path = '/' + server_url.split('/', 3)[-1] if server_url.count('/') > 2 else ''

        # Parse paths
        paths = spec.get('paths', {})
        for path, methods in paths.items():
            if not isinstance(methods, dict):
                continue

            full_path = base_path + path

            for method, details in methods.items():
                if method.upper() not in HTTP_METHODS_UPPER:
                    continue

                summary = ''
                if isinstance(details, dict):
                    summary = details.get('summary', details.get('operationId', ''))

                apis.append(APICall(
                    type='spec',
                    method=method.upper(),
                    path=full_path,
                    file=str(file_path),
                    line=1,
                    library='openapi',
                    function_name=summary if summary else None
                ))

    except (json.JSONDecodeError, KeyError, TypeError):
        pass

    return apis


def scan_directory(project_path: Path) -> list[APICall]:
    """Scan a directory for all API calls and endpoints"""
    all_apis = []

    for root, dirs, files in os.walk(project_path):
        # Filter out ignored directories
        dirs[:] = [d for d in dirs if not should_skip_dir(d)]

        for file in files:
            file_path = Path(root) / file
            suffix = file_path.suffix.lower()

            if suffix not in FRONTEND_EXTENSIONS | BACKEND_EXTENSIONS | SPEC_EXTENSIONS:
                continue

            try:
                content = file_path.read_text(encoding='utf-8')
            except (UnicodeDecodeError, PermissionError):
                continue

            # Check frontend patterns
            if suffix in FRONTEND_EXTENSIONS:
                all_apis.extend(find_frontend_apis(file_path, content))

            # Check backend patterns
            if suffix in BACKEND_EXTENSIONS:
                all_apis.extend(find_backend_apis(file_path, content))

            # Check OpenAPI specs
            if suffix in SPEC_EXTENSIONS:
                all_apis.extend(find_openapi_specs(file_path, content))

    # Deduplicate
    seen = set()
    unique_apis = []
    for api in all_apis:
        key = (api.type, api.method, api.path, api.file, api.line)
        if key not in seen:
            seen.add(key)
            unique_apis.append(api)

    return unique_apis


def format_markdown(apis: list[APICall], project_path: str) -> str:
    """Format API list as markdown"""
    frontend = [a for a in apis if a.type == 'frontend']
    backend = [a for a in apis if a.type == 'backend']
    specs = [a for a in apis if a.type == 'spec']

    output = f"# API Discovery Report\n\n"
    output += f"**Project:** `{project_path}`\n"
    output += f"**Total APIs Found:** {len(apis)}\n"
    output += f"- Frontend Calls: {len(frontend)}\n"
    output += f"- Backend Endpoints: {len(backend)}\n"
    output += f"- OpenAPI Specs: {len(specs)}\n\n"

    if specs:
        output += "## OpenAPI Specifications\n\n"
        output += "| Method | Path | Summary | File |\n"
        output += "|--------|------|---------|------|\n"
        for api in sorted(specs, key=lambda x: (x.file, x.path, x.method)):
            rel_path = os.path.relpath(api.file, project_path)
            summary = api.function_name or '-'
            output += f"| `{api.method}` | `{api.path}` | {summary} | `{rel_path}` |\n"
        output += "\n"

    if backend:
        output += "## Backend Endpoints\n\n"
        output += "| Method | Path | Library | File | Line |\n"
        output += "|--------|------|---------|------|------|\n"
        for api in sorted(backend, key=lambda x: (x.path, x.method)):
            rel_path = os.path.relpath(api.file, project_path)
            output += f"| `{api.method}` | `{api.path}` | {api.library} | `{rel_path}` | {api.line} |\n"
        output += "\n"

    if frontend:
        output += "## Frontend API Calls\n\n"
        output += "| Method | Path | Library | Instance | File | Line |\n"
        output += "|--------|------|---------|----------|------|------|\n"
        for api in sorted(frontend, key=lambda x: (x.path, x.method)):
            rel_path = os.path.relpath(api.file, project_path)
            instance = api.instance_name or '-'
            output += f"| `{api.method}` | `{api.path}` | {api.library} | {instance} | `{rel_path}` | {api.line} |\n"

    return output


def format_json_for_inspector(apis: list[APICall]) -> list[dict]:
    """Format APIs for PromptInspector component consumption"""
    result = []
    seen_paths = set()

    for api in apis:
        # Create unique ID
        api_id = f"{api.method}_{api.path}".replace('/', '_').replace('{', '').replace('}', '')

        # Skip duplicates (same method + path)
        key = (api.method, api.path)
        if key in seen_paths:
            continue
        seen_paths.add(key)

        result.append({
            'id': api_id,
            'method': api.method,
            'path': api.path,
            'description': api.function_name or f"{api.library} - {os.path.basename(api.file)}"
        })

    return result


def main():
    parser = argparse.ArgumentParser(description='Discover APIs in a project')
    parser.add_argument('project_path', help='Path to the project directory')
    parser.add_argument('--output', choices=['json', 'markdown', 'inspector'], default='markdown',
                        help='Output format (default: markdown, inspector for PromptInspector format)')
    args = parser.parse_args()

    project_path = Path(args.project_path).resolve()

    if not project_path.exists():
        print(f"Error: Path '{project_path}' does not exist")
        return 1

    apis = scan_directory(project_path)

    if args.output == 'json':
        print(json.dumps([asdict(api) for api in apis], indent=2))
    elif args.output == 'inspector':
        print(json.dumps(format_json_for_inspector(apis), indent=2))
    else:
        print(format_markdown(apis, str(project_path)))

    return 0


if __name__ == '__main__':
    exit(main())
