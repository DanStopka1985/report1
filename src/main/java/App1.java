import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.concurrent.CountDownLatch;
import java.util.stream.IntStream;

//Эмуляция поиска по случайному коду для 200 условных пользователей
public final class App1 {
    private static final Integer NO_THREADS = 200;
    private App1() {
    }

    public static void main(final String[] args) throws InterruptedException {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(
                "jdbc:postgresql://127.0.0.1/test?user=postgres&password=postgres");
        config.setConnectionTimeout(60000);
        HikariDataSource ds = new HikariDataSource(config);


        CountDownLatch startLatch = new CountDownLatch(NO_THREADS);
        CountDownLatch finishLatch = new CountDownLatch(NO_THREADS);

        Runnable readingThread = () -> {
            //Случайный выбор кода для поиска
            String code = getRandomCode(ds);
            startLatch.countDown();
            try {
                startLatch.await();
            } catch (InterruptedException ex) {
                System.out.println("Synchronization failure: "
                        + ex.getMessage());
                return;
            }

            //Вывод результата поиска для случайного кода
            printIndivBySnils(ds, code);

            finishLatch.countDown();
        };

        IntStream.range(0, NO_THREADS).forEach(
                (index) -> new Thread(readingThread).start()
        );

        finishLatch.await();
        System.out.println("All reading thread complete.");

    }

//Случайный выбор кода для поиска
    private static String getRandomCode(HikariDataSource ds){
        String code = "";
        try (Connection db = ds.getConnection()) {
            try (PreparedStatement query =
                         db.prepareStatement("select code from indiv_code where id = (select (random() * max(id))::int from indiv_code)"
                         ))
            {
                ResultSet rs = query.executeQuery();
                while (rs.next()) {
                    code = rs.getString(1);
                }
                rs.close();
            }
        } catch (SQLException ex) {
            System.out.println("Database connection failure: "
                    + ex.getMessage());
        }
        return code;
    }

    //Вывод результата поиска для случайного кода
    private static void printIndivBySnils(HikariDataSource ds, String snils) {
        try (Connection db = ds.getConnection()) {
            try (PreparedStatement query =
                         db.prepareStatement("select coalesce(\n" +
                                 "               (select sname from indiv i where i.id  = (select indiv_id from indiv_code ic where ic.code = ? and type_id = 1)), 'indiv not found'\n" +
                                 "           )"
                         ))
            {
                query.setString(1, snils);
                ResultSet rs = query.executeQuery();
                while (rs.next()) {
                    System.out.println(rs.getString(1));
                }
                rs.close();
            }
        } catch (SQLException ex) {
            System.out.println("Database connection failure: "
                    + ex.getMessage());
        }
    }
}
