<%@ page import="java.sql.*, java.time.LocalDate" %>
<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<!DOCTYPE html>
<html>
<head>
    <title>Database Restore Tracker Dashboard</title>
    <link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.10.24/css/jquery.dataTables.min.css">
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script src="https://cdn.datatables.net/1.10.24/js/jquery.dataTables.min.js"></script>
    <script>
        // Auto-refresh every 10 seconds
        setInterval(function(){
            location.reload();
        }, 10000);
    </script>

    <style>
        body {
            font-family: Arial, sans-serif;
            background: #f7f9fb;
            padding: 20px;
        }
        h2 {
            color: #333;
        }
        table.dataTable tbody tr.today-row {
            background-color: #d4edda !important; /* green */
        }
        table.dataTable tbody tr.failed-row {
            background-color: #f8d7da !important; /* red */
        }
        table.dataTable tbody tr.pending-row {
            background-color: #fff3cd !important; /* yellow */
        }
    </style>
</head>
<body>

<h2>Database Restore Tracker Dashboard</h2>

<table id="datatable" class="display">
    <thead>
        <tr>
            <th>ID</th>
            <th>DB Name</th>
            <th>Backup Date</th>
            <th>Restore Status</th>
            <th>Health Status</th>
            <th>Last Updated</th>
        </tr>
    </thead>
    <tbody>
        <%
            try {
                Class.forName("com.mysql.cj.jdbc.Driver");
                Connection con = DriverManager.getConnection(
                    "jdbc:mysql://172.16.16.108:3306/restore_tracker_db?useSSL=false&serverTimezone=Asia/Kolkata&allowPublicKeyRetrieval=true",
                    "root",
                    "1G8323AuR$"
                );

                Statement stmt = con.createStatement();
                ResultSet rs = stmt.executeQuery("SELECT * FROM db_restore_tracker ORDER BY backup_date DESC, last_updated DESC");

                LocalDate today = LocalDate.now();

                while(rs.next()) {
                    String restoreStatus = rs.getString("restore_status");
                    java.sql.Date backupDate = rs.getDate("backup_date");

                    // Determine row class based on status or date
                    String rowClass = "";
                    if (backupDate != null && backupDate.toLocalDate().equals(today)) {
                        rowClass = "today-row";
                    } else if ("failed".equalsIgnoreCase(restoreStatus)) {
                        rowClass = "failed-row";
                    } else if ("pending".equalsIgnoreCase(restoreStatus)) {
                        rowClass = "pending-row";
                    }
        %>
                    <tr class="<%= rowClass %>">
                        <td><%= rs.getInt("id") %></td>
                        <td><%= rs.getString("db_name") %></td>
                        <td><%= backupDate %></td>
                        <td><%= restoreStatus %></td>
                        <td><%= rs.getString("health_status") %></td>
                        <td><%= rs.getTimestamp("last_updated") %></td>
                    </tr>
        <%
                }
                rs.close();
                stmt.close();
                con.close();
            } catch(Exception e) {
                out.println("<tr><td colspan='6'>Error: " + e.getMessage() + "</td></tr>");
            }
        %>
    </tbody>
</table>

<script>
    $(document).ready(function() {
        $('#datatable').DataTable({
            "order": [[2, "desc"]] // backup_date column
        });
    });
</script>

</body>
</html>
