#!/usr/bin/env python3
"""
Auto-setup script for Prompt Inspector

Automatically detects project type and injects the component.
Supports: Next.js (App Router / Pages Router)

Usage:
    python setup.py <project_path>
"""

import os
import sys
import re
import shutil
from pathlib import Path

COMPONENT_IMPORT = "import { PromptInspector } from '@/components/PromptInspector';"

def get_version_from_file(file_path: Path) -> str | None:
    """Extract version from PromptInspector.tsx file."""
    if not file_path.exists():
        return None
    content = file_path.read_text(encoding='utf-8')
    match = re.search(r"PROMPT_INSPECTOR_VERSION\s*=\s*['\"]([^'\"]+)['\"]", content)
    return match.group(1) if match else '1.0.0'  # Default to 1.0.0 for old versions
COMPONENT_JSX = """{process.env.NODE_ENV === 'development' && <PromptInspector />}"""

def find_project_type(project_path: Path) -> dict:
    """Detect project type and find the appropriate layout file."""
    result = {
        'type': None,
        'layout_file': None,
        'components_dir': None,
    }

    # Check for Next.js App Router
    app_layout = project_path / 'app' / 'layout.tsx'
    app_layout_js = project_path / 'app' / 'layout.js'

    # Check for src directory structure
    src_app_layout = project_path / 'src' / 'app' / 'layout.tsx'
    src_app_layout_js = project_path / 'src' / 'app' / 'layout.js'

    # Check for Pages Router
    pages_app = project_path / 'pages' / '_app.tsx'
    pages_app_js = project_path / 'pages' / '_app.js'
    src_pages_app = project_path / 'src' / 'pages' / '_app.tsx'
    src_pages_app_js = project_path / 'src' / 'pages' / '_app.js'

    # Determine layout file
    if app_layout.exists():
        result['type'] = 'nextjs-app'
        result['layout_file'] = app_layout
        result['components_dir'] = project_path / 'components'
    elif app_layout_js.exists():
        result['type'] = 'nextjs-app'
        result['layout_file'] = app_layout_js
        result['components_dir'] = project_path / 'components'
    elif src_app_layout.exists():
        result['type'] = 'nextjs-app'
        result['layout_file'] = src_app_layout
        result['components_dir'] = project_path / 'src' / 'components'
    elif src_app_layout_js.exists():
        result['type'] = 'nextjs-app'
        result['layout_file'] = src_app_layout_js
        result['components_dir'] = project_path / 'src' / 'components'
    elif pages_app.exists():
        result['type'] = 'nextjs-pages'
        result['layout_file'] = pages_app
        result['components_dir'] = project_path / 'components'
    elif pages_app_js.exists():
        result['type'] = 'nextjs-pages'
        result['layout_file'] = pages_app_js
        result['components_dir'] = project_path / 'components'
    elif src_pages_app.exists():
        result['type'] = 'nextjs-pages'
        result['layout_file'] = src_pages_app
        result['components_dir'] = project_path / 'src' / 'components'
    elif src_pages_app_js.exists():
        result['type'] = 'nextjs-pages'
        result['layout_file'] = src_pages_app_js
        result['components_dir'] = project_path / 'src' / 'components'

    return result


def compare_versions(v1: str, v2: str) -> int:
    """Compare two version strings. Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2."""
    def parse(v):
        return [int(x) for x in v.split('.')]
    p1, p2 = parse(v1), parse(v2)
    for a, b in zip(p1, p2):
        if a < b:
            return -1
        if a > b:
            return 1
    return 0


def copy_component(components_dir: Path, script_dir: Path, force_update: bool = False) -> bool:
    """Copy PromptInspector component to project."""
    components_dir.mkdir(parents=True, exist_ok=True)

    source = script_dir.parent / 'assets' / 'PromptInspector.tsx'
    dest = components_dir / 'PromptInspector.tsx'

    if not source.exists():
        print(f"  Error: Source component not found at {source}")
        return False

    source_version = get_version_from_file(source)
    dest_version = get_version_from_file(dest)

    if dest.exists():
        if dest_version and source_version:
            comparison = compare_versions(source_version, dest_version)
            if comparison > 0:
                # Newer version available
                print(f"\n  ╔════════════════════════════════════════════════════════════╗")
                print(f"  ║  🆕 UPDATE AVAILABLE                                        ║")
                print(f"  ╠════════════════════════════════════════════════════════════╣")
                print(f"  ║  Current version: {dest_version:<10}                              ║")
                print(f"  ║  Latest version:  {source_version:<10}                              ║")
                print(f"  ╚════════════════════════════════════════════════════════════╝")

                if force_update:
                    response = 'y'
                else:
                    response = input("\n  Update to latest version? [Y/n]: ").strip().lower()

                if response in ('', 'y', 'yes'):
                    # Backup existing
                    backup = dest.with_suffix('.tsx.backup')
                    shutil.copy(dest, backup)
                    print(f"  📦 Backup saved to {backup.name}")

                    shutil.copy(source, dest)
                    print(f"  ✅ Updated to v{source_version}")
                    return True
                else:
                    print(f"  ⏭️  Skipped update (keeping v{dest_version})")
                    return True
            elif comparison == 0:
                print(f"  ✅ Component is up to date (v{dest_version})")
                return True
            else:
                print(f"  ⚠️  Local version (v{dest_version}) is newer than source (v{source_version})")
                return True
        else:
            print(f"  Component already exists at {dest}")
            return True

    shutil.copy(source, dest)
    print(f"  ✅ Installed PromptInspector v{source_version}")
    return True


def inject_into_layout(layout_file: Path, project_type: str) -> bool:
    """Inject the component into the layout file."""
    content = layout_file.read_text(encoding='utf-8')

    # Check if already injected
    if 'PromptInspector' in content:
        print(f"  Component already injected in {layout_file}")
        return True

    lines = content.split('\n')
    new_lines = []
    import_added = False
    component_added = False

    for i, line in enumerate(lines):
        # Add import after the last import statement
        if not import_added and (line.startswith('import ') or line.startswith('from ')):
            new_lines.append(line)
            # Check if next line is not an import
            if i + 1 < len(lines) and not lines[i + 1].startswith('import ') and not lines[i + 1].startswith('from ') and lines[i + 1].strip() != '':
                new_lines.append(COMPONENT_IMPORT)
                import_added = True
            continue

        new_lines.append(line)

        # For App Router: inject before closing </body> or </html>
        if project_type == 'nextjs-app':
            if '</body>' in line and not component_added:
                indent = len(line) - len(line.lstrip())
                new_lines.insert(-1, ' ' * (indent + 2) + COMPONENT_JSX)
                component_added = True

        # For Pages Router: inject inside Component wrapper
        elif project_type == 'nextjs-pages':
            if '<Component' in line and not component_added:
                # Find the closing of the return statement and inject before it
                pass

    # If import wasn't added (no imports found), add at top
    if not import_added:
        new_lines.insert(0, COMPONENT_IMPORT)
        new_lines.insert(1, '')

    # For Pages Router, try different injection point
    if project_type == 'nextjs-pages' and not component_added:
        new_content = '\n'.join(new_lines)
        # Find return statement and inject component
        if 'return (' in new_content or 'return(' in new_content:
            # Add before the closing of the main wrapper
            new_content = new_content.replace(
                '</Component>',
                f'</Component>\n        {COMPONENT_JSX}'
            )
            new_lines = new_content.split('\n')
            component_added = True

    new_content = '\n'.join(new_lines)

    # Backup original
    backup_file = layout_file.with_suffix(layout_file.suffix + '.backup')
    if not backup_file.exists():
        shutil.copy(layout_file, backup_file)
        print(f"  Backup created at {backup_file}")

    layout_file.write_text(new_content, encoding='utf-8')
    print(f"  Injected component into {layout_file}")

    return True


def main():
    if len(sys.argv) < 2:
        print("Usage: python setup.py <project_path> [options]")
        print("\nAutomatically sets up Prompt Inspector in your project.")
        print("\nOptions:")
        print("  --check, -c    Check for updates only (no installation)")
        print("  --force, -y    Auto-accept updates without prompting")
        return 1

    # Parse arguments
    args = sys.argv[1:]
    project_path = None
    force_update = False
    check_only = False

    for arg in args:
        if arg in ('--force', '-y'):
            force_update = True
        elif arg in ('--check', '-c'):
            check_only = True
        elif not project_path:
            project_path = Path(arg).resolve()

    if not project_path:
        print("Error: Project path is required")
        return 1

    script_dir = Path(__file__).parent

    if not project_path.exists():
        print(f"Error: Path '{project_path}' does not exist")
        return 1

    print(f"Detecting project type in {project_path}...")

    project_info = find_project_type(project_path)

    if not project_info['type']:
        print("Could not detect project type.")
        print("Supported: Next.js (App Router / Pages Router)")
        print("\nManual setup required. Copy PromptInspector.tsx to your components folder")
        print("and import it in your root layout/app file.")
        return 1

    print(f"Detected: {project_info['type']}")
    print(f"Layout file: {project_info['layout_file']}")
    print(f"Components dir: {project_info['components_dir']}")

    # Check-only mode
    if check_only:
        source = script_dir.parent / 'assets' / 'PromptInspector.tsx'
        dest = project_info['components_dir'] / 'PromptInspector.tsx'

        source_version = get_version_from_file(source)
        dest_version = get_version_from_file(dest)

        print(f"\n  Version Check:")
        print(f"  ├─ Installed: {dest_version or 'Not installed'}")
        print(f"  └─ Latest:    {source_version}")

        if not dest.exists():
            print("\n  ⚠️  PromptInspector is not installed. Run without --check to install.")
            return 1
        elif dest_version and source_version and compare_versions(source_version, dest_version) > 0:
            print("\n  🆕 Update available! Run without --check to update.")
            return 1
        else:
            print("\n  ✅ Up to date!")
            return 0

    print("\nSetting up Prompt Inspector...")

    # Step 1: Copy component
    if not copy_component(project_info['components_dir'], script_dir, force_update):
        return 1

    # Step 2: Inject into layout
    if not inject_into_layout(project_info['layout_file'], project_info['type']):
        return 1

    print("\nSetup complete!")
    print("Run your dev server and look for the toolbar in the bottom-right corner.")
    print("The component only loads in development mode.")

    return 0


if __name__ == '__main__':
    sys.exit(main())
