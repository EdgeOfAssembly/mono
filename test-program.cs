using System;

class TestProgram {
    static int Main() {
        Console.WriteLine("=== Mono Build Verification Test ===");

        // Basic arithmetic
        int a = 42, b = 58;
        if (a + b != 100) { Console.WriteLine("FAIL: arithmetic"); return 1; }

        // String operations
        string s = "Hello" + " " + "Mono";
        if (s != "Hello Mono") { Console.WriteLine("FAIL: string concat"); return 1; }

        // Array operations
        int[] arr = new int[] { 1, 2, 3, 4, 5 };
        int sum = 0;
        for (int i = 0; i < arr.Length; i++) sum += arr[i];
        if (sum != 15) { Console.WriteLine("FAIL: array sum"); return 1; }

        // Generics
        System.Collections.Generic.List<int> list = new System.Collections.Generic.List<int>();
        list.Add(10);
        list.Add(20);
        if (list.Count != 2 || list[0] != 10) { Console.WriteLine("FAIL: generics"); return 1; }

        // Exception handling
        bool caught = false;
        try { throw new InvalidOperationException("test"); }
        catch (InvalidOperationException) { caught = true; }
        if (!caught) { Console.WriteLine("FAIL: exceptions"); return 1; }

        Console.WriteLine("ALL TESTS PASSED");
        return 0;
    }
}
