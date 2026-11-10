package ni.edu.uam.ecometer;
import ni.edu.uam.ecometer.config.ConexionBD;

import java.sql.Connection;
import java.sql.SQLException;

public class PruebaConexion {

    public static void main(String[] args) {

        try (Connection conexion = ConexionBD.conectar()) {

            if (conexion != null && !conexion.isClosed()) {

                System.out.println("================================");
                System.out.println(" CONEXION EXITOSA A ECOMETER");
                System.out.println("================================");

                System.out.println(
                        "Base de datos: " +
                                conexion.getCatalog()
                );

                System.out.println(
                        "Estado: Conectado"
                );
            }

        } catch (SQLException e) {

            System.out.println("ERROR DE CONEXION");
            System.out.println(e.getMessage());

        }
    }
}
