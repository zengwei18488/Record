{{- $local_vuls := . -}}
<!DOCTYPE html>
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title>Trivy Vulnerability Report</title>
    <style>
      body { background-color: #f3f4f6; font-family: sans-serif; color: #111827; padding: 20px; }
      h1 { color: #1f2937; }
      .summary { margin-bottom: 20px; background: white; padding: 15px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
      table { border-collapse: collapse; width: 100%; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
      th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #e5e7eb; }
      th { background-color: #1f2937; color: white; font-weight: 600; text-transform: uppercase; font-size: 0.85rem; }
      tr:hover { background-color: #f9fafb; }
      .severity { font-weight: bold; padding: 4px 8px; border-radius: 4px; font-size: 0.75rem; text-transform: uppercase; }
      .severity-CRITICAL { background-color: #fee2e2; color: #991b1b; }
      .severity-HIGH { background-color: #ffedd5; color: #9a3412; }
      .severity-MEDIUM { background-color: #fef9c3; color: #854d0e; }
      .severity-LOW { background-color: #f0fdf4; color: #166534; }
      .links a { color: #2563eb; text-decoration: none; }
      .links a:hover { text-decoration: underline; }
    </style>
  </head>
  <body>
    <h1>Trivy 漏洞扫描报告</h1>
    <div class="summary">
      <p><strong>扫描对象:</strong> {{ (index . 0).Target }}</p>
      <p><strong>生成时间:</strong> {{ now }}</p>
    </div>
    <table>
      <thead>
        <tr>
          <th>编号</th>
          <th>严重程度</th>
          <th>软件包</th>
          <th>当前版本</th>
          <th>修复版本</th>
          <th>链接</th>
        </tr>
      </thead>
      <tbody>
        {{- range . }}
          {{- range .Vulnerabilities }}
          <tr>
            <td>{{ .VulnerabilityID }}</td>
            <td><span class="severity severity-{{ .Severity }}">{{ .Severity }}</span></td>
            <td>{{ .PkgName }}</td>
            <td>{{ .InstalledVersion }}</td>
            <td>{{ if .FixedVersion }}{{ .FixedVersion }}{{ else }}<em>无补丁</em>{{ end }}</td>
            <td class="links"><a href="{{ .PrimaryURL }}" target="_blank">查看详情</a></td>
          </tr>
          {{- end }}
        {{- end }}
      </tbody>
    </table>
  </body>
</html>
