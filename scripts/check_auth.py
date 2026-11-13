"""Read-only authentication diagnostics. Never print credentials or response bodies."""
import base64
import json
import os
from pathlib import Path
import urllib.error
import urllib.request

import yaml


def formatting(value):
    return {'present': bool(value),
            'contains_whitespace': any(c.isspace() for c in value),
            'surrounded_by_quotes': len(value) > 1 and value[0] == value[-1] and value[0] in "\"'",
            'is_securestring_label': value == 'System.Security.SecureString',
            'contains_non_ascii': not value.isascii()}


def probe(url, headers):
    req = urllib.request.Request(url, headers={**headers, 'User-Agent': 'tradewinds-auth-diagnostic'})
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            return response.status
    except urllib.error.HTTPError as error:
        error.close()
        return error.code
    except (OSError, ValueError):
        return 'connection_or_header_error'


def diagnose(cfg):
    github = os.environ.get('GITHUB_TOKEN') or os.environ.get('GH_TOKEN') or ''
    email, jira = os.environ.get('JIRA_EMAIL', ''), os.environ.get('JIRA_API_TOKEN', '')
    result = {'format': {'github_token': formatting(github), 'jira_token': formatting(jira),
                         'jira_email_present': bool(email), 'jira_email_contains_at': '@' in email}}
    if github:
        headers = {'Authorization': 'Bearer ' + github, 'Accept': 'application/vnd.github+json'}
        result['github_account_http'] = probe('https://api.github.com/user', headers)
        result['github_repository_http'] = probe('https://api.github.com/repos/' + cfg['github']['repository'], headers)
    if email and jira:
        headers = {'Authorization': 'Basic ' + base64.b64encode(f'{email}:{jira}'.encode()).decode()}
        result['jira_site_http'] = probe(cfg['jira']['url'].rstrip('/') + '/rest/api/3/myself', headers)
        cloud_id = cfg['jira'].get('cloud_id')
        if cloud_id:
            gateway = 'https://api.atlassian.com/ex/jira/' + cloud_id
            result['jira_scoped_gateway_http'] = probe(gateway + '/rest/api/3/myself', headers)
            if result['jira_scoped_gateway_http'] == 200 and result['jira_site_http'] != 200:
                result['jira_api_url_to_set'] = gateway
    return result


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    cfg = yaml.safe_load((root / 'harness.yaml').read_text(encoding='utf-8'))
    print(json.dumps(diagnose(cfg), indent=2))
