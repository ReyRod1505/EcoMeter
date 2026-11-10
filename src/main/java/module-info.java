module ni.edu.uam.ecometer {
    requires javafx.controls;
    requires javafx.fxml;
    requires java.sql;


    opens ni.edu.uam.ecometer to javafx.fxml;
    exports ni.edu.uam.ecometer;
}